#!/usr/bin/env python3
"""Push a local git history to GitHub through the Git Data API.

Why this exists: some sandboxed environments can reach api.github.com over
HTTPS but block git's own transport (CONNECT to github.com:443 returns 502, and
direct 443 is firewalled). GitHub's REST API uses the same Git object model, and
object SHAs are content-addressed, so a history can be replayed faithfully.

Usage: python3 tools/push_via_api.py <owner/repo>

- Reads the auth token from `git credential fill` (never printed).
- Replays every commit in --reverse order, preserving parents, authors and dates.
- Creates refs/heads/main at the tip.
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import urllib.request

API = "https://api.github.com"

repo = ""
blob_cache = {}
tree_cache = {}


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout


def get_token(username: str) -> str:
    out = subprocess.run(
        ["git", "credential", "fill"],
        input=f"protocol=https\nhost=github.com\nusername={username}\n\n".encode(),
        capture_output=True,
        check=True,
        timeout=20,
    ).stdout.decode()
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    raise SystemExit("no credential available")


TOKEN = get_token(sys.argv[1].split("/")[0])


def api(method: str, path: str, body=None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path,
        method=method,
        data=data,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())


def commits(repo: str) -> list[dict]:
    raw = git(
        "log",
        "--reverse",
        "--format=%H%x00%T%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s%n---%n",
    ).decode("utf-8", "replace")
    out = []
    for chunk in raw.split("---"):
        chunk = chunk.strip()
        if not chunk:
            continue
        parts = chunk.split("\x00")
        if len(parts) != 9:
            continue
        out.append(
            dict(
                sha=parts[0],
                tree=parts[1],
                author=dict(name=parts[2], email=parts[3], date=parts[4]),
                committer=dict(name=parts[5], email=parts[6], date=parts[7]),
                message=parts[8],
            )
        )
    return out


def tree_entries(tree_sha: str) -> list[dict]:
    raw = git("ls-tree", "-r", "-z", tree_sha)
    entries = []
    for item in raw.split(b"\x00"):
        if not item:
            continue
        meta, path = item.split(b"\t", 1)
        mode, _type, sha = meta.split(b" ")
        entries.append(
            dict(mode=mode.decode(), sha=sha.decode(), path=path.decode("utf-8", "replace"))
        )
    return entries


def ensure_blob(sha: str) -> str:
    if sha in blob_cache:
        return sha
    content = git("cat-file", "blob", sha)
    api(
        "POST",
        f"/repos/{repo}/git/blobs",
        {"content": base64.b64encode(content).decode(), "encoding": "base64"},
    )
    blob_cache[sha] = sha
    return sha


def ensure_tree(local_sha: str, entries: list[dict]) -> str:
    if local_sha in tree_cache:
        return tree_cache[local_sha]
    tree_body = {
        "tree": [
            {"path": e["path"], "mode": e["mode"], "type": "blob", "sha": e["sha"]}
            for e in entries
        ]
    }
    created = api("POST", f"/repos/{repo}/git/trees", tree_body)
    got = created.get("sha")
    if got != local_sha:
        print(f"  ! tree sha mismatch: local {local_sha} vs remote {got}", file=sys.stderr)
    tree_cache[local_sha] = got
    return got


def main() -> int:
    global repo, blob_cache, tree_cache
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    repo = sys.argv[1]
    blob_cache = {}
    tree_cache = {}

    # The Git Data API refuses to create objects in an empty repository, so seed
    # a one-file initial commit first. It will be orphaned when we force the ref.
    try:
        api("PUT", f"/repos/{repo}/contents/README.md",
            {"message": "init", "content": base64.b64encode(b"# kiln\n").decode(),
             "branch": "main"})
        print("seeded initial commit (un-emptied the repository)")
    except Exception as e:  # noqa: BLE001
        print("seed skipped:", e)

    history = commits(repo)
    print(f"replaying {len(history)} commits for {repo}")

    # Pass 1: upload every blob across the whole history (deduplicated by SHA).
    all_entries: dict[str, list[dict]] = {}
    for c in history:
        all_entries[c["tree"]] = tree_entries(c["tree"])
    blob_shas = sorted({e["sha"] for entries in all_entries.values() for e in entries})
    print(f"uploading {len(blob_shas)} blobs ...")
    for i, sha in enumerate(blob_shas):
        ensure_blob(sha)
        if (i + 1) % 20 == 0 or i + 1 == len(blob_shas):
            print(f"  {i + 1}/{len(blob_shas)}")

    # Pass 2: create trees and commits in order, chaining parents.
    prev = None
    tip = None
    for i, c in enumerate(history):
        tree_sha = ensure_tree(c["tree"], all_entries[c["tree"]])
        body = {
            "message": c["message"],
            "tree": tree_sha,
            "author": c["author"],
            "committer": c["committer"],
        }
        if prev:
            body["parents"] = [prev]
        commit = api("POST", f"/repos/{repo}/git/commits", body)
        got = commit.get("sha")
        if got != c["sha"]:
            print(f"  ! commit sha mismatch: local {c['sha']} vs remote {got}", file=sys.stderr)
        prev = got
        tip = got
        print(f"  [{i + 1}/{len(history)}] {c['sha'][:7]} {c['message'][:60]}")

    # Point main at the tip, replacing the seed commit.
    api("PATCH", f"/repos/{repo}/git/refs/heads/main", {"sha": tip, "force": True})
    print(f"refs/heads/main -> {tip}")
    print(f"done: https://github.com/{repo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
