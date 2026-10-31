"""Check real compiled CLI exit codes and machine-readable JSON."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SCRATCH = ROOT / "work" / "cli-check"
SCRATCH.mkdir(parents=True, exist_ok=True)
count = 0


def run(cli, arguments, expected):
    global count
    path = ROOT / "_build/js/debug/build/cmd" / cli / f"{cli}.js"
    p = subprocess.run(["node", str(path), *map(str, arguments)], cwd=ROOT,
                       capture_output=True, encoding="utf-8", timeout=20)
    assert p.returncode == expected, (arguments, p.returncode, p.stdout, p.stderr)
    result = json.loads(p.stdout)
    count += 1
    return result


def main():
    selection = "examples/models/selection.json"
    unsat = "examples/models/selection_unsat.json"
    pdir = "examples/regression/pricing/"
    old, new = pdir + "before.json", pdir + "after.json"
    baseline = pdir + "baseline.json"
    assert run("model", ["validate", selection], 0)["valid"]
    solved = run("model", ["solve", selection], 0)
    assert solved["complete"] and len(solved["solutions"]) == 1
    assert run("model", ["minimize", selection], 0)["value"] == 12
    core = run("model", ["explain", unsat], 0)
    assert core["irreducible"] and set(core["rule_ids"]) == {
        "two-algebra", "shared-stem-a-b", "shared-stem-a-c", "require-a"}
    assert not run("model", ["solve", selection, "--budget", "0"], 3)["complete"]
    assert run("model", ["explain", unsat, "--budget", "0"], 3)["stop"] == "budget_limit"
    assert run("model", ["solve", selection, "--limit", "1"], 3)["stop"] == "solution_limit"
    for args in [["solve", selection, "--budget", "typo"], ["solve", selection, "--limit", "0"],
                 ["solve", selection, "--budget", "1", "--budget", "2"],
                 ["solve", selection, "--unknown", "1"], ["solve", "missing.json"],
                 ["minimize", "examples/models/cubic.json"], ["verify", selection]]:
        assert "error" in run("model", args, 2)
    witness = SCRATCH / "case.json"
    witness.write_text(json.dumps(solved["solutions"][0]), encoding="utf-8")
    assert run("model", ["verify", selection, "--assignment", witness], 0)["valid"]
    witness.write_text(json.dumps(dict(solved["solutions"][0], A=1)), encoding="utf-8")
    assert not run("model", ["verify", selection, "--assignment", witness], 1)["valid"]
    result = run("regression", ["diff", old, new], 1)
    assert result["relation"] == "changed" and len(result["changes"]) == 4
    witness.write_text(json.dumps(result["changes"][0]["assignment"]), encoding="utf-8")
    assert run("regression", ["replay", old, new, "--assignment", witness], 0)["direction"] == "rejected_by_new"
    assert run("regression", ["closest", old, new, "--baseline", baseline], 1)["minimal"]
    assert run("regression", ["diff", old, new, "--budget", "0"], 3)["relation"] == "unknown"
    assert run("regression", ["diff", old, new, "--limit", "1"], 1)["complete"] is False
    edir = "examples/regression/equivalent/"
    assert run("regression", ["diff", edir + "before.json", edir + "after.json"], 0)["relation"] == "equivalent"
    for args in [["diff", old, new, "--budget", "nope"], ["closest", old, new],
                 ["replay", old, new], ["diff", old, new, "--baseline", baseline],
                 ["diff", "missing.json", new]]:
        assert "error" in run("regression", args, 2)
    witness.write_text(json.dumps({"tier": 0, "subtotal": 50, "coupon": 0, "discount": 0}), encoding="utf-8")
    assert not run("regression", ["replay", old, new, "--assignment", witness], 1)["witness"]
    print(f"CLI integration checks passed: {count}")


if __name__ == "__main__":
    main()
