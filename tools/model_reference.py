"""Independent full-assignment interpreter and fixed-order exhaustive oracle.

Uses Python arbitrary-precision arithmetic before applying the documented range
contract. Does not import MoonBit output, legacy kiln arithmetic or search code.
Rule evaluation happens only after every referenced variable has been bound.
This deliberately avoids the partial evaluator / MRV algorithm under test.
"""
from __future__ import annotations
import json
from pathlib import Path
import sys

LIMIT = 10**12


class Undefined(Exception):
    pass


def term(t, env):
    if isinstance(t, int):
        result = t
    elif isinstance(t, str):
        result = env[t]
    else:
        op, *args = t
        if op == "indicator":
            answer = rule(args[0], env)
            if answer is None:
                raise Undefined("undefined indicator")
            return int(answer)
        nums = [term(a, env) for a in args]
        if op == "neg":
            result = -nums[0]
        elif op == "abs":
            result = abs(nums[0])
        else:
            a, b = nums
            if op == "+":
                result = a + b
            elif op == "-":
                result = a - b
            elif op == "*":
                result = a * b
            elif op in ("/", "%"):
                if b == 0:
                    raise Undefined("zero denominator")
                quotient = (abs(a) // abs(b)) * (-1 if (a < 0) != (b < 0) else 1)
                result = quotient if op == "/" else a - quotient * b
            else:
                raise ValueError(op)
    if abs(result) > LIMIT:
        raise Undefined("out of range")
    return result


def rule(r, env):
    """True/False/None; None is undefined, never silently false under not."""
    op, *args = r
    if op in ("all", "any", "not", "implies", "count", "holds"):
        if op == "holds":
            return rule(args[0], env) is True
        if op == "implies":
            return rule(["any", ["not", args[0]], args[1]], env)
        if op == "not":
            answer = rule(args[0], env)
            return None if answer is None else not answer
        children = args[2] if op == "count" else args
        answers = [rule(child, env) for child in children]
        if op == "all":
            return False if False in answers else None if None in answers else True
        if op == "any":
            return True if True in answers else None if None in answers else False
        if None in answers:
            return None
        return args[0] <= answers.count(True) <= args[1]
    try:
        if op == "distinct":
            values = [term(t, env) for t in args]
            return len(values) == len(set(values))
        if op == "table":
            values = [term(t, env) for t in args[0]]
            return values in args[1]
        a, b = [term(t, env) for t in args]
        return {"==": a == b, "!=": a != b, "<": a < b, "<=": a <= b,
                ">": a > b, ">=": a >= b}[op]
    except Undefined:
        return None


def term_names(t):
    if isinstance(t, str):
        return {t}
    if isinstance(t, int):
        return set()
    if t[0] == "indicator":
        return rule_names(t[1])
    return set().union(*(term_names(a) for a in t[1:]))


def rule_names(r):
    op, *args = r
    if op == "count":
        return set().union(*(rule_names(a) for a in args[2]))
    if op in ("all", "any", "not", "implies", "holds"):
        return set().union(*(rule_names(a) for a in args))
    if op == "table":
        args = args[0]
    return set().union(*(term_names(a) for a in args))


def verify(doc, env):
    variables = doc["variables"]
    return (set(env) == {v["name"] for v in variables}
            and all(env[v["name"]] in v["domain"] for v in variables)
            and all(rule(r["assert"], env) is True for r in doc["rules"]))


def solutions(doc):
    constraints = [(rule_names(r["assert"]), r["assert"]) for r in doc["rules"]]
    env = {}
    answer = []

    def dfs(index):
        if any(names <= env.keys() and rule(r, env) is not True for names, r in constraints):
            return
        if index == len(doc["variables"]):
            answer.append(dict(env))
            return
        variable = doc["variables"][index]
        for value in variable["domain"]:
            env[variable["name"]] = value
            dfs(index + 1)
        env.pop(variable["name"], None)

    dfs(0)
    return answer


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python tools/model_reference.py model.json result.json")
    doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
    # Embedded model is authoritative for a counterexample task. This is a
    # consistency checker, not authentication of the submitted model's origin.
    if result.get("operation") == "counterexample":
        doc = result["model"]
    actual = result["solutions"]
    if not all(verify(doc, a) for a in actual):
        raise SystemExit("INVALID witness")
    if result["complete"]:
        canonical = lambda items: {tuple(sorted(a.items())) for a in items}
        expected = canonical(solutions(doc))
        if canonical(actual) != expected or len(actual) != len(expected):
            raise SystemExit("INCORRECT complete solution set")
    print(f"verified {len(actual)} witnesses; complete={result['complete']}")


if __name__ == "__main__":
    main()
