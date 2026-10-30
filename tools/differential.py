"""Reproducible independent solution-set differential test, seed 20261031."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
import time
from model_reference import solutions, verify, term, Undefined

ROOT = Path(__file__).resolve().parents[1]
RNG = random.Random(20261031)


def random_term(names, depth=2):
    if depth == 0 or RNG.random() < .40:
        return RNG.choice(names + [-3, -2, -1, 0, 1, 2, 3, 10**12])
    op = RNG.choice(["+", "-", "*", "/", "%", "abs", "neg"])
    return [op, *[random_term(names, depth - 1) for _ in range(1 if op in ("abs", "neg") else 2)]]


def random_rule(names, depth=2):
    op = RNG.choice(["==", "!=", "<", "<=", ">", ">=", "all", "any", "not", "implies", "distinct", "table", "count"])
    if depth == 0:
        op = RNG.choice(["==", "!=", "<", "<=", ">", ">="])
    if op in ("all", "any", "not", "implies"):
        n = 1 if op == "not" else 2 if op == "implies" else RNG.randrange(4)
        return [op, *[random_rule(names, depth - 1) for _ in range(n)]]
    if op == "count":
        children = [random_rule(names, depth - 1) for _ in range(RNG.randrange(4))]
        lo = RNG.randrange(len(children) + 1)
        return [op, lo, RNG.randrange(lo, len(children) + 1), children]
    if op == "distinct":
        return [op, *[random_term(names) for _ in range(RNG.randrange(4))]]
    if op == "table":
        terms = [random_term(names) for _ in range(RNG.randrange(3))]
        return [op, terms, [[RNG.randrange(-3, 4) for _ in terms] for _ in range(RNG.randrange(5))]]
    return [op, random_term(names), random_term(names)]


def random_model():
    names = [f"x{i}" for i in range(RNG.randrange(1, 5))]
    return {"format": "kiln.model/1",
            "variables": [{"name": n, "domain": RNG.sample(range(-3, 4), RNG.randrange(1, 5))} for n in names],
            "rules": [{"id": f"r{i}", "assert": random_rule(names)} for i in range(RNG.randrange(5))],
            "objective": random_term(names)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", type=int, default=800)
    parser.add_argument("--compiled", default="_build/js/debug/build/api/api.js")
    parser.add_argument("--out", default="work/differential")
    args = parser.parse_args()
    proc = subprocess.Popen(["node", "tools/model_rpc.mjs", args.compiled], cwd=ROOT,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8")

    def call(doc, **options):
        proc.stdin.write(json.dumps({"model": doc, **options}, ensure_ascii=False) + "\n")
        proc.stdin.flush()
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError(proc.stderr.read())
        result = json.loads(line)
        assert "error" not in result and "adapter_error" not in result, result
        return result

    canonical = lambda assignments: {tuple(sorted(a.items())) for a in assignments}
    models = [(p.stem, json.loads(p.read_text(encoding="utf-8")))
              for p in sorted((ROOT / "examples/models").glob("*.json"))]
    models += [(f"random-{i:04}", random_model()) for i in range(args.cases)]
    raw = []
    start = time.perf_counter()
    interrupted_checks = optimization_checks = witness_checks = 0
    try:
        for index, (name, doc) in enumerate(models):
            oracle = solutions(doc)
            t0 = time.perf_counter()
            result = call(doc, budget=10_000_000, limit=1_000_000)
            elapsed = (time.perf_counter() - t0) * 1000
            assert result["complete"] and result["stop"] == "exhausted", (name, result)
            assert canonical(result["solutions"]) == canonical(oracle), (name, doc, result, oracle)
            assert len(result["solutions"]) == len(oracle), (name, "duplicate witnesses")
            expected_class = "unsatisfiable" if not oracle else "unique" if len(oracle) == 1 else "multiple"
            assert result["classification"] == expected_class
            assert all(verify(doc, a) for a in result["solutions"]), name
            for a in result["solutions"][:2]:
                assert call(doc, operation="verify", assignment=a)["valid"]
                witness_checks += 1
            if index % 7 == 0:
                budget = index % 19
                bounded = call(doc, budget=budget)
                assert bounded["statistics"]["probes"] <= budget
                assert canonical(bounded["solutions"]) <= canonical(oracle)
                if bounded["complete"]:
                    assert canonical(bounded["solutions"]) == canonical(oracle)
                else:
                    assert bounded["classification"] in ("unknown", "multiple")
                interrupted_checks += 1
            if "objective" in doc and (index < 7 or index % 4 == 0):
                values = []
                for a in oracle:
                    try:
                        values.append(term(doc["objective"], a))
                    except Undefined:
                        pass
                optimized = call(doc, operation="minimize", budget=10_000_000)
                assert optimized["stop"] == "exhausted"
                assert optimized["value"] == (min(values) if values else None), (name, optimized, values)
                assert optimized["optimal"] == bool(values)
                if values:
                    assert verify(doc, optimized["assignment"])
                    assert term(doc["objective"], optimized["assignment"]) == min(values)
                optimization_checks += 1
            raw.append({"case": name, "sha256": hashlib.sha256(json.dumps(doc, sort_keys=True).encode()).hexdigest(),
                        "solutions": len(oracle), **result["statistics"], "rpc_ms": round(elapsed, 3)})
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    out = ROOT / args.out
    out.mkdir(parents=True, exist_ok=True)
    summary = {"seed": 20261031, "models": len(models), "random_models": args.cases,
               "complete_solution_sets_matched": len(raw), "witness_checks": witness_checks,
               "interrupted_checks": interrupted_checks, "optimization_checks": optimization_checks,
               "satisfiable_models": sum(r["solutions"] > 0 for r in raw),
               "elapsed_seconds": round(time.perf_counter() - start, 3),
               "method": "independent Python full-assignment evaluator and fixed-order DFS vs compiled MoonBit MRV/partial evaluator"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (out / "cases.jsonl").write_text("".join(json.dumps(r) + "\n" for r in raw), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
