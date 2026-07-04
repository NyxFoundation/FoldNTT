#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""
Drives tb_stream.v (real compact_bf_v2 + tf_rom_fold under iverilog) through
a full N=1024 NTT and INTT, and checks the results against the bit-exact
golden.  This is the RTL end-to-end evidence for the paper's evaluation: the
invented modules, wired into a complete transform, compute

  NTT(x)          == the reference DIT_NR_NTT on the real twiddle table
  INTT(NTT(x))    == x   (exact — the issue-#7 halving fix works at the
                          full-transform level, not just per butterfly)

Prints "STREAM SIM PASS" / exit 0 iff both hold on every tested vector.
"""

import os
import re
import subprocess
import sys
import random

Q = 12289
N, LOGN = 1024, 10
HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "..", "cfntt_ref", "hardware_code_radix-2")


def load_w():
    with open(os.path.join(RTL, "tf_ROM.v")) as fh:
        entries = {int(a): int(v) for a, v in
                   re.findall(r"10'd(\d+):\s*Q\s*<=\s*14'd(\d+);", fh.read())}
    return [1] + [entries[a] for a in range(1023)]


W = load_w()


def ntt_golden(x):
    a = x[:]
    r = 1
    for p in range(LOGN - 1, -1, -1):
        J = 1 << p
        for k in range(N // (2 * J)):
            w = W[r]
            r += 1
            for j in range(J):
                lo, hi = k * 2 * J + j, k * 2 * J + j + J
                t = (a[hi] * w) % Q
                a[lo], a[hi] = (a[lo] + t) % Q, (a[lo] - t) % Q
    return a


def build():
    out = os.path.join(HERE, "sim_stream")
    srcs = [os.path.join(HERE, "tb_stream.v"),
            os.path.join(HERE, "..", "..", "kred-butterfly", "compact_bf_v2.v"),
            os.path.join(HERE, "..", "..", "kred-butterfly", "modular_mul_kred.v"),
            os.path.join(HERE, "..", "..", "psi-fold-rom", "tf_rom_fold.v"),
            os.path.join(RTL, "modular_add.v"),
            os.path.join(RTL, "modular_substraction.v"),
            os.path.join(RTL, "modular_half.v"),
            os.path.join(RTL, "common_lib.v")]
    subprocess.run(["iverilog", "-g2005", "-o", out] + srcs, check=True)
    return out


def main():
    sim = build()
    wdir = os.path.join(HERE, "run_stream")
    os.makedirs(wdir, exist_ok=True)
    rng = random.Random(0)

    ok_vectors = 0
    for trial in range(2):
        x = [rng.randrange(Q) for _ in range(N)]
        with open(os.path.join(wdir, "stream_in.hex"), "w") as fh:
            fh.write("\n".join("%04x" % v for v in x) + "\n")
        r = subprocess.run(["vvp", sim], cwd=wdir, capture_output=True,
                           text=True)
        if "RT_DONE" not in r.stdout:
            print("FAIL: sim did not finish\n%s" % r.stdout[-800:])
            sys.exit(1)

        def rd(name):
            with open(os.path.join(wdir, name)) as fh:
                vals = []
                for line in fh:
                    line = line.split("//")[0].strip()
                    if line and not line.startswith("@"):
                        if "x" in line.lower():
                            print("FAIL: X in %s" % name)
                            sys.exit(1)
                        vals.append(int(line, 16))
                return vals

        ntt = rd("stream_ntt.hex")
        rt = rd("stream_rt.hex")
        gold = ntt_golden(x)
        if ntt != gold:
            bad = next(i for i in range(N) if ntt[i] != gold[i])
            print("FAIL: NTT mismatch at %d: %d != %d" % (bad, ntt[bad], gold[bad]))
            sys.exit(1)
        if rt != x:
            bad = next(i for i in range(N) if rt[i] != x[i])
            print("FAIL: roundtrip mismatch at %d: %d != %d" % (bad, rt[bad], x[bad]))
            sys.exit(1)
        ok_vectors += 1
        print("ok  vector %d: RTL NTT == golden; INTT(NTT(x)) == x exactly"
              % trial)

    print("(compact_bf_v2 + tf_rom_fold under iverilog, %d vectors)" % ok_vectors)
    print("STREAM SIM PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
