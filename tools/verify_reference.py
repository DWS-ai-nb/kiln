#!/usr/bin/env python3
"""Reference verifier for kiln paper files.

This file exists to make a claim checkable rather than rhetorical: the answer
certificate is a *format*, not an internal detail. Anyone can re-check a paper
with sixty lines of Python and no MoonBit toolchain.

It deliberately shares nothing with the MoonBit implementation — different
language, different runtime, independent code. If both accept a paper, the
paper is almost certainly correct; if they disagree, one of them has a bug and
that is worth knowing.

Usage:
    python3 tools/verify_reference.py out/paper.json
Exit code is 0 when every item verifies, 1 otherwise.
"""

from __future__ import annotations

import json
import sys
from fractions import Fraction


def exact_sqrt(value: Fraction) -> Fraction | None:
    """Square root of a non-negative rational, or None when it is irrational."""
    if value < 0:
        return None
    n, d = value.numerator, value.denominator
    rn, rd = isqrt(n), isqrt(d)
    if rn * rn != n or rd * rd != d:
        return None
    return Fraction(rn, rd)


def isqrt(n: int) -> int:
    """Integer square root without importing math (kept explicit on purpose)."""
    if n < 0:
        raise ValueError("negative")
    if n < 2:
        return n
    lo, hi = 0, n
    while lo <= hi:
        mid = (lo + hi) // 2
        sq = mid * mid
        if sq == n:
            return mid
        if sq < n:
            lo = mid + 1
        else:
            hi = mid - 1
    return hi


def verify_quadratic(payload: list[str], answers: list[str]) -> str | None:
    """None means well-posed; otherwise a human-readable reason."""
    if len(payload) != 3:
        return f"payload 应有 3 个数，实际 {len(payload)}"
    a, b, c = (Fraction(x) for x in payload)
    if a == 0:
        return "not-quadratic"
    d = b * b - 4 * a * c
    if d < 0:
        return "no-real-roots"
    if d == 0:
        return "double-root"
    s = exact_sqrt(d)
    if s is None:
        return "irrational-roots"
    r1 = (-b + s) / (2 * a)
    r2 = (-b - s) / (2 * a)
    got = sorted({r1, r2})
    want = sorted({Fraction(x) for x in answers})
    if got != want:
        return f"answer-mismatch: formula gives {got}, declared {want}"
    return None


def verify_rational(payload: list[str], answers: list[str]) -> str | None:
    """`(n0 + n1*x) / (d0 + d1*x) = q`"""
    if len(payload) != 5:
        return f"payload 应有 5 个数，实际 {len(payload)}"
    n0, n1, d0, d1, q = (Fraction(x) for x in payload)
    # Cross-multiply: (n0 + n1 x) - q (d0 + d1 x) = 0
    b1 = n1 - q * d1
    b0 = n0 - q * d0
    if b1 == 0:
        return "identity" if b0 == 0 else "no-solution"
    x = -b0 / b1
    if d0 + d1 * x == 0:
        return "extraneous-root"
    if len(answers) != 1 or Fraction(answers[0]) != x:
        return f"answer-mismatch: equation gives {x}, declared {answers}"
    return None


VERIFIERS = {
    "quadratic": verify_quadratic,
    "rational": verify_rational,
}


def verify_file(path: str) -> int:
    with open(path, encoding="utf-8") as handle:
        paper = json.load(handle)

    if paper.get("format") != "kiln.paper/1":
        print(f"unsupported format: {paper.get('format')!r}")
        return 1

    items = paper.get("items", [])
    failures = 0
    for index, item in enumerate(items, start=1):
        family = item.get("family")
        verifier = VERIFIERS.get(family)
        if verifier is None:
            print(f"{index}: unknown family {family!r}")
            failures += 1
            continue
        reason = verifier(item.get("payload", []), item.get("answers", []))
        if reason is not None:
            print(f"{index}: {reason}  ({item.get('question')})")
            failures += 1

    print(
        f"schema={paper.get('schema')} items={len(items)} "
        f"passed={len(items) - failures} failed={failures}"
    )
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(verify_file(sys.argv[1]))
