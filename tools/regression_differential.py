"""Independent oracle for changed acceptance sets and minimum Hamming witnesses."""
from __future__ import annotations
import argparse
import copy
import itertools
import json
from pathlib import Path
import random
import subprocess
import time
from differential import random_model, random_rule, partial_semantics_models
from model_reference import solutions, verify

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=800)
    ap.add_argument("--out", default="work/regression-differential")
    ap.add_argument("--compiled", default="_build/js/debug/build/api/api.js")
    args = ap.parse_args()
    rng = random.Random(20261031)
    proc = subprocess.Popen(["node", "tools/model_rpc.mjs", args.compiled], cwd=ROOT,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8")

    def call(before, after, **options):
        proc.stdin.write(json.dumps({"model": before, "after": after, **options}) + "\n")
        proc.stdin.flush()
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError(proc.stderr.read())
        result = json.loads(line)
        assert "error" not in result and "adapter_error" not in result, result
        return result

    pairs = []
    for p in sorted((ROOT / "examples/regression").iterdir()):
        before = json.loads((p / "before.json").read_text(encoding="utf-8"))
        after = json.loads((p / "after.json").read_text(encoding="utf-8"))
        baseline = json.loads((p / "baseline.json").read_text(encoding="utf-8"))
        pairs.append((p.name, before, after, baseline))
    for name, before in partial_semantics_models():
        after = copy.deepcopy(before)
        after["rules"] = [{"id": "reject-all", "assert": ["any"]}]
        pairs.append((name, before, after, {"x": 1}))
    for i in range(args.cases):
        before = random_model()
        after = copy.deepcopy(before)
        names = [v["name"] for v in before["variables"]]
        # Include semantic rewrites/unchanged versions, rule edits, reordering,
        # changed domains (including empty domains), and objective-only edits.
        if i % 5:
            after["rules"] = [{"id": f"new-{k}", "assert": random_rule(names)} for k in range(rng.randrange(4))]
        if i % 3 == 0:
            rng.shuffle(after["variables"])
        if i % 4 == 0:
            for v in after["variables"]:
                v["domain"] = rng.sample(range(-3, 4), rng.randrange(5))
        domains = {v["name"]: set(v["domain"]) for v in before["variables"]}
        for v in after["variables"]:
            domains[v["name"]].update(v["domain"])
        baseline = {n: rng.choice(sorted(values)) for n, values in domains.items()}
        pairs.append((f"pair-{i:04}", before, after, baseline))
    raw = []
    closest_checks = bounded_checks = 0
    begin = time.perf_counter()
    try:
        for i, (name, before, after, baseline) in enumerate(pairs):
            keys = lambda aa: {tuple(sorted(a.items())) for a in aa}
            old = keys(solutions(before))
            new = keys(solutions(after))
            changed = old ^ new
            result = call(before, after, operation="compare", budget=10_000_000, limit=1_000_000)
            assert result["complete"], (name, result)
            actual = keys(c["assignment"] for c in result["changes"])
            assert actual == changed and len(result["changes"]) == len(changed), (name, result, changed)
            assert result["relation"] == ("changed" if changed else "equivalent")
            for c in result["changes"]:
                a = c["assignment"]
                ov, nv = verify(before, a), verify(after, a)
                assert ov != nv and c["before_valid"] == ov and c["after_valid"] == nv
                assert c["direction"] == ("rejected_by_new" if ov else "accepted_by_new")
            if i < 4 or i % 3 == 0:
                r = call(before, after, operation="closest", baseline=baseline, budget=10_000_000)
                expected = min((sum(value != baseline[k] for k, value in a) for a in changed), default=None)
                assert r["stop"] == "exhausted" and r["distance"] == expected, (name, r, expected)
                assert r["minimal"] == bool(changed)
                if changed:
                    assert tuple(sorted(r["change"]["assignment"].items())) in changed
                    assert sum(v != baseline[k] for k, v in r["change"]["assignment"].items()) == expected
                closest_checks += 1
            if i % 11 == 0:
                budget = i % 23
                r = call(before, after, operation="compare", budget=budget)
                actual = keys(c["assignment"] for c in r["changes"])
                assert actual <= changed and r["statistics"]["probes"] <= budget
                if r["complete"]:
                    assert actual == changed
                elif not actual:
                    assert r["relation"] == "unknown"
                bounded_checks += 1
            raw.append({"case": name, "old_accepted": len(old), "new_accepted": len(new),
                        "removed": len(old - new), "added": len(new - old), **result["statistics"]})
    finally:
        proc.stdin.close()
        proc.wait(timeout=10)
    out = ROOT / args.out
    out.mkdir(parents=True, exist_ok=True)
    summary = {"seed": 20261031, "model_pairs": len(pairs), "complete_differences_matched": len(raw),
               "minimum_hamming_checks": closest_checks, "bounded_comparison_checks": bounded_checks,
               "equivalent_pairs": sum(r["added"] + r["removed"] == 0 for r in raw),
               "elapsed_seconds": round(time.perf_counter() - begin, 3),
               "oracle": "symmetric difference of independently enumerated old/new accepted assignment sets"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (out / "cases.jsonl").write_text("".join(json.dumps(r) + "\n" for r in raw), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
