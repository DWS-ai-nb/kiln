#!/usr/bin/env python3
"""Push incremental changes to GitHub through the Git Data API.

Companion to push_via_api.py (which replays a full history). This one diffs the
local HEAD tree against the remote main tree and creates a single commit with
only the changed files, using the remote tree as its base.

Usage: python3 tools/sync_incremental.py <owner/repo> "<commit message>"
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"


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


def api(method: str, path: str, body=None, expect_error: bool = False) -> dict:
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
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if expect_error:
            return {"_error": e.code, "_body": e.read().decode()}
        raise


def main() -> int:
    global TOKEN
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    repo = sys.argv[1]
    message = sys.argv[2]
    owner = repo.split("/")[0]
    TOKEN = get_token(owner)

    # Remote main.
    ref = api("GET", f"/repos/{repo}/git/ref/heads/main")
    remote_commit_sha = ref["object"]["sha"]
    remote_commit = api("GET", f"/repos/{repo}/git/commits/{remote_commit_sha}")
    remote_tree_sha = remote_commit["tree"]["sha"]
    remote_tree = api("GET", f"/repos/{repo}/git/trees/{remote_tree_sha}?recursive=1")
    remote_files = {
        e["path"]: e["sha"] for e in remote_tree.get("tree", []) if e["type"] == "blob"
    }

    # Local HEAD tree.
    local_files = {}
    for line in git("ls-files", "-s").decode().splitlines():
        parts = line.split()
        mode, sha, path = parts[0], parts[1], parts[3]
        local_files[path] = (sha, mode)

    changed = {
        path: (sha, mode)
        for path, (sha, mode) in local_files.items()
        if remote_files.get(path) != sha
    }
    print(f"changed files: {len(changed)}")
    for path in sorted(changed):
        print(f"  {path}")

    # Ensure all blobs exist on the remote.
    for path, (sha, _mode) in changed.items():
        existing = api("GET", f"/repos/{repo}/git/blobs/{sha}", expect_error=True)
        if "_error" in existing:
            content = git("cat-file", "blob", sha)
            api(
                "POST",
                f"/repos/{repo}/git/blobs",
                {"content": base64.b64encode(content).decode(), "encoding": "base64"},
            )

    # Build a tree with the remote tree as base and only changed entries.
    entries = [
        {"path": path, "mode": mode, "type": "blob", "sha": sha}
        for path, (sha, mode) in changed.items()
    ]
    tree = api(
        "POST",
        f"/repos/{repo}/git/trees",
        {"base_tree": remote_tree_sha, "tree": entries},
    )
    new_tree_sha = tree["sha"]

    commit = api(
        "POST",
        f"/repos/{repo}/git/commits",
        {
            "message": message,
            "tree": new_tree_sha,
            "parents": [remote_commit_sha],
        },
    )
    api(
        "PATCH",
        f"/repos/{repo}/git/refs/heads/main",
        {"sha": commit["sha"], "force": True},
    )
    print(f"pushed: {commit['sha']}")
    print(f"done: https://github.com/{repo}/commit/{commit['sha']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
