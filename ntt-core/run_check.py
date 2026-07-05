#!/usr/bin/env python3
"""newcore verification driver — independent checks, all freshness-enforced:

  1. Whole-core ROUND-TRIP: load x, run NTT then INTT on the banked RAM with
     our own FSM, assert INTT(NTT(x)) == x for all N — on NRT vectors
     (deterministic ramp + seeded random), back-to-back (tb_ntt_core.v).
  2. NTT GOLDEN: every post-NTT memory dump equals the *Python* golden NTT
     built from the reference tf_ROM.v table (independent of the shared RTL
     leaf modules — a common-mode leaf bug cannot pass this).
  3. INTT GOLDEN: for INTT-only vectors y, ntt_golden(INTT_rtl(y)) == y.
     Since the golden NTT is bijective, this proves the core's INTT is the
     exact inverse of the *golden* NTT at these points, not merely of its own
     NTT.
  4. SCHEDULE CROSS-VALIDATION: the new core's post-NTT memory is bit-identical
     to the golden streaming harness (verification/fullcore/tb_stream.v) on the
     same input.

Every dump file is deleted before simulation and required to exist after it,
and simulator exit codes are checked — stale files can never pass (this
regressed once: the dumps went to a renamed directory and check 4 silently
compared two committed files).

Run from the repo root (needs iverilog on PATH, e.g. `nix develop`):
    python3 ntt-core/run_check.py
Exit 0 iff all checks pass.
"""
import glob
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "verification", "fullcore"))
from run_stream import ntt_golden  # golden from the real tf_ROM.v table

NRT, NIV = 4, 2  # must match tb_ntt_core.v

RTL = [
    "kred-butterfly/compact_bf_v2.v",
    "kred-butterfly/modular_mul_kred.v",
    "psi-fold-rom/tf_rom_fold.v",
    "cfntt_ref/hardware_code_radix-2/modular_add.v",
    "cfntt_ref/hardware_code_radix-2/modular_substraction.v",
    "cfntt_ref/hardware_code_radix-2/modular_half.v",
    "cfntt_ref/hardware_code_radix-2/common_lib.v",
]

DUMPS = ([f"ntt-core/nc_in_{t}.hex" for t in range(NRT)]
         + [f"ntt-core/nc_ntt_{t}.hex" for t in range(NRT)]
         + [f"ntt-core/nc_iin_{t}.hex" for t in range(NIV)]
         + [f"ntt-core/nc_intt_{t}.hex" for t in range(NIV)])
STREAM_DUMPS = ["stream_ntt.hex", "stream_rt.hex"]


def fail(msg, extra=""):
    print("FAIL:", msg)
    if extra:
        print(extra)
    sys.exit(1)


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def iverilog(out, srcs):
    r = sh(f"iverilog -g2012 -o {out} " + " ".join(srcs))
    if r.returncode:
        fail("iverilog failed", r.stdout + r.stderr)


def load_hex(path):
    vals = []
    for line in open(path):
        s = line.split("//")[0].strip()
        if s:
            if "x" in s.lower():
                fail(f"X value in {path}")
            vals.append(int(s, 16))
    if len(vals) != 1024:
        fail(f"{path}: expected 1024 values, got {len(vals)}")
    return vals


def clean(paths):
    for p in paths:
        if os.path.exists(p):
            os.remove(p)


def require_fresh(paths):
    missing = [p for p in paths if not os.path.exists(p)]
    if missing:
        fail(f"simulation did not (re)write: {', '.join(missing)}")


def main():
    # stale-dump guard: anything the sims are supposed to write is removed
    # first and must exist afterwards
    clean(glob.glob("ntt-core/nc_*.hex") + ["stream_in.hex"] + STREAM_DUMPS)

    # 1. new core: multi-vector round-trip + all dumps
    iverilog("/tmp/nc.vvp", ["ntt-core/ntt_core.v", "ntt-core/tb_ntt_core.v"] + RTL)
    r = sh("vvp /tmp/nc.vvp")
    if r.returncode != 0 or "NTT_CORE ALL PASS" not in r.stdout \
            or "TIMEOUT" in r.stdout:
        fail("new-core simulation", r.stdout[-2000:] + r.stderr[-500:])
    require_fresh(DUMPS)
    print(f"round-trip: PASS ({NRT} vectors, INTT(NTT(x)) == x exactly)")

    # transform latency, measured (the paper's ~74k-cycle claim traces here)
    import re
    cycles = [int(c) for c in re.findall(r"TRANSFORM mode=\d cycles=(\d+)",
                                         r.stdout)]
    if len(cycles) != 2 * NRT + NIV:
        fail(f"expected {2*NRT+NIV} transform cycle reports, got {len(cycles)}")
    if not all(70_000 <= c <= 80_000 for c in cycles):
        fail(f"transform cycle count out of budget: {sorted(set(cycles))}")
    print(f"latency:     PASS (measured {min(cycles)}..{max(cycles)} "
          f"cycles per 1024-pt transform)")

    # 2. NTT golden (independent Python model on the real twiddle table)
    for t in range(NRT):
        x = load_hex(f"ntt-core/nc_in_{t}.hex")
        y = load_hex(f"ntt-core/nc_ntt_{t}.hex")
        if y != ntt_golden(x):
            bad = next(i for i in range(1024) if y[i] != ntt_golden(x)[i])
            fail(f"NTT golden mismatch, vector {t}, index {bad}")
    print(f"NTT golden:  PASS ({NRT} vectors, core NTT == Python golden)")

    # 3. INTT golden: golden-NTT(core-INTT(y)) == y  (bijectivity argument)
    for t in range(NIV):
        y = load_hex(f"ntt-core/nc_iin_{t}.hex")
        z = load_hex(f"ntt-core/nc_intt_{t}.hex")
        if ntt_golden(z) != y:
            fail(f"INTT golden mismatch, vector {t}")
    print(f"INTT golden: PASS ({NIV} vectors, core INTT inverts the golden NTT)")

    # 4. schedule cross-validation vs the golden streaming harness (vector 0)
    shutil.copy("ntt-core/nc_in_0.hex", "stream_in.hex")
    iverilog("/tmp/st.vvp", ["verification/fullcore/tb_stream.v"] + RTL)
    r = sh("vvp /tmp/st.vvp")
    if r.returncode != 0 or "RT_DONE" not in r.stdout:
        fail("streaming harness simulation", r.stdout[-2000:] + r.stderr[-500:])
    require_fresh(STREAM_DUMPS)
    if load_hex("stream_ntt.hex") != load_hex("ntt-core/nc_ntt_0.hex"):
        fail("cross-validation: new-core NTT != streaming harness NTT")
    print("cross-validation: PASS (new-core NTT == golden streaming NTT)")

    print("NEWCORE: ALL PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
