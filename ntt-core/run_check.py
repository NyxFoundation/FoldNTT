#!/usr/bin/env python3
"""newcore verification driver — two independent checks, both under iverilog:

  1. Whole-core ROUND-TRIP: load x, run NTT then INTT on the banked RAM with
     our own FSM, assert INTT(NTT(x)) == x for all N (tb_ntt_core.v).
  2. NTT CROSS-VALIDATION: the new core's post-NTT memory is bit-identical to
     the golden streaming harness (verification/fullcore/tb_stream.v) on the same
     input — so the core computes the *correct* NTT, not merely an invertible
     one.

Run from the repo root (needs iverilog on PATH, e.g. `nix develop`):
    python3 ntt-core/run_check.py
Exit 0 iff both checks pass.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

RTL = [
    "kred-butterfly/compact_bf_v2.v",
    "kred-butterfly/modular_mul_kred.v",
    "psi-fold-rom/tf_rom_fold.v",
    "cfntt_ref/hardware_code_radix-2/modular_add.v",
    "cfntt_ref/hardware_code_radix-2/modular_substraction.v",
    "cfntt_ref/hardware_code_radix-2/modular_half.v",
    "cfntt_ref/hardware_code_radix-2/common_lib.v",
]


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def iverilog(out, srcs):
    r = sh(f"iverilog -g2012 -o {out} " + " ".join(srcs))
    if r.returncode:
        print(r.stdout, r.stderr)
        sys.exit("iverilog failed")


def load_hex(path):
    vals = []
    for line in open(path):
        s = line.strip()
        if s and not s.startswith("//"):
            vals.append(int(s, 16))
    return vals


def main():
    # 1. new core: round-trip + dump nc_in.hex / nc_ntt.hex
    iverilog("/tmp/nc.vvp", ["ntt-core/ntt_core.v", "ntt-core/tb_ntt_core.v"] + RTL)
    out = sh("vvp /tmp/nc.vvp").stdout
    rt_ok = "NTT_CORE ROUND-TRIP PASS" in out
    print("round-trip:", "PASS" if rt_ok else "FAIL")
    if not rt_ok:
        print(out)

    # 2. golden streaming harness on the SAME input
    sh("cp ntt-core/nc_in.hex stream_in.hex")
    iverilog("/tmp/st.vvp", ["verification/fullcore/tb_stream.v"] + RTL)
    sh("vvp /tmp/st.vvp")
    a, b = load_hex("ntt-core/nc_ntt.hex"), load_hex("stream_ntt.hex")
    xv_ok = len(a) == len(b) == 1024 and a == b
    print("cross-validation:", "PASS" if xv_ok else "FAIL",
          f"(new-core NTT == golden streaming NTT, {len(a)}/{len(b)})")

    ok = rt_ok and xv_ok
    print("NEWCORE:", "ALL PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
