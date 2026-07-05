#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""
Prime scout: enumerate Proth primes q = k*2^m + 1 whose k has signed-digit
weight <= 2 (k = 2^a +/- 1), i.e. the primes for which the K-RED fold costs
at most one adder/subtractor per fold — the selection criterion
docs/algorithm-level.md proposes for new protocol parameters.

For each hit we print the fold count F (from kred_gen's planner) and the
smallest shift-friendly psi (signed-digit weight <= 2) that is a primitive
2048-th root of unity, i.e. supports the N = 1024 negacyclic NTT with a
multiplier-free psi-fold ROM ('-' if none of the small candidates works;
the psi-fold then needs a constant multiply instead).

Windows scanned: 14-16 bit (Falcon-class), 28-32 bit (BabyBear-class),
60-64 bit (RNS/FHE-class).  Run: uv run generator/prime_scout.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kred_gen import plan_kred

MR_BASES = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)  # exact for < 2^64


def is_prime(n):
    if n < 2:
        return False
    for p in MR_BASES:
        if n % p == 0:
            return n == p
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for a in MR_BASES:
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = x * x % n
            if x == n - 1:
                break
        else:
            return False
    return True


def shift_friendly_psi(q, n=1024):
    """Smallest psi with signed-digit weight <= 2 that is a primitive
    2n-th root mod q (psi^n == -1)."""
    if (q - 1) % (2 * n):
        return None
    cands = sorted({(1 << a) + s for a in range(1, 8) for s in (-1, 1)})
    for psi in cands:
        if 1 < psi < q and pow(psi, n, q) == q - 1:
            return psi
    return None


WINDOWS = [(14, 16), (28, 32), (60, 64)]
KNOWN = {12289: "Falcon", 3329: "Kyber", 8380417: "Dilithium",
         2013265921: "BabyBear", (2**32 - 1) * 2**32 + 1: "Goldilocks"}


def main():
    print(f"{'q':>22}  {'k':>12}  {'m':>3}  {'F':>2}  {'psi':>4}  note")
    for lo, hi in WINDOWS:
        print(f"-- {lo}-{hi} bit --")
        rows = []
        for a in range(1, hi):
            for s in (-1, 1):
                k = (1 << a) + s
                if k < 1 or k % 2 == 0:
                    continue
                for m in range(12, hi + 1):
                    q = k * (1 << m) + 1
                    if not (lo <= q.bit_length() <= hi):
                        continue
                    if not is_prime(q):
                        continue
                    F = len(plan_kred(q)["folds"])
                    psi = shift_friendly_psi(q)
                    rows.append((q, k, a, s, m, F, psi))
        seen = set()
        for q, k, a, s, m, F, psi in sorted(set(rows)):
            if q in seen:
                continue
            seen.add(q)
            kform = f"2^{a}{'+' if s > 0 else '-'}1"
            note = KNOWN.get(q, "")
            print(f"{q:>22}  {kform:>12}  {m:>3}  {F:>2}  "
                  f"{psi if psi else '-':>4}  {note}")


if __name__ == "__main__":
    main()
