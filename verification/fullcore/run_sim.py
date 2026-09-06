#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""
Full-core RTL simulation driver (iverilog): runs NTT then INTT on the
RECONSTRUCTED-FSM cores and checks the bank contents against the bit-exact
golden model.

  reference core (shipped compact_bf + tf_ROM + reconstructed fsm):
      expects NTT exact, and the round-trip scaled by 2^10 (upstream
      issue #7 REPRODUCED at full-core RTL level).
  v2 core (compact_bf_v2 + modular_mul_kred + tf_rom_fold):
      expects NTT exact and the round-trip EXACT.

Data mapping mirrors the proven conflict-free map: polynomial coefficient
at address a lives in bank parity(a), offset a>>1.

Prints "FULLCORE SIM PASS" and exits 0 iff every comparison matches.
"""

import os
import re
import subprocess
import sys
import random

Q = 12289
INV9 = pow(9, -1, Q)
N, LOGN = 1024, 10
HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "..", "cfntt_ref", "hardware_code_radix-2")


def load_w():
    with open(os.path.join(RTL, "tf_ROM.v")) as fh:
        entries = {int(a): int(v) for a, v in
                   re.findall(r"10'd(\d+):\s*Q\s*<=\s*14'd(\d+);", fh.read())}
    return [1] + [entries[a] for a in range(1023)]


W = load_w()


def ntt_golden(a):
    """DIT_NR_NTT on the real twiddle table (v2's 9^-1 scaling cancels
    against the K-RED factor, so both cores target the same golden)."""
    a = a[:]
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


def parity(x):
    return bin(x).count("1") & 1


def to_banks(vec):
    b = ([0] * 512, [0] * 512)
    for a, val in enumerate(vec):
        b[parity(a)][a >> 1] = val
    return b


def from_banks(b0, b1):
    return [(b1 if parity(a) else b0)[a >> 1] for a in range(N)]


def write_hex(path, words):
    with open(path, "w") as fh:
        fh.write("\n".join("%04x" % w for w in words) + "\n")


def read_hex(path, expect=512):
    words = []
    with open(path) as fh:
        for line in fh:
            line = line.split("//")[0].strip()
            if line and not line.startswith("@"):
                words.append(int(line, 16))
    if len(words) != expect:
        raise SystemExit("FAIL: %s holds %d words, expected %d" % (path, len(words), expect))
    return words


def build(variant):
    out = os.path.join(HERE, "sim_%s" % variant)
    srcs = [os.path.join(HERE, "tb_fullcore.v"),
            os.path.join(HERE, "fsm_recon.v"),
            os.path.join(RTL, "address_generator.v"),
            os.path.join(RTL, "conflict_free_memory_map.v"),
            os.path.join(RTL, "arbiter.v"),
            os.path.join(RTL, "network_bank_in.v"),
            os.path.join(RTL, "network_bf_in.v"),
            os.path.join(RTL, "network_bf_out.v"),
            os.path.join(RTL, "data_bank.v"),
            os.path.join(RTL, "tf_address_generator.v"),
            os.path.join(RTL, "modular_add.v"),
            os.path.join(RTL, "modular_substraction.v"),
            os.path.join(RTL, "modular_half.v"),
            os.path.join(RTL, "common_lib.v")]
    if variant == "v2":
        srcs += [os.path.join(HERE, "top_poly_mul_v2.v"),
                 os.path.join(HERE, "..", "..", "kred-butterfly", "compact_bf_v2.v"),
                 os.path.join(HERE, "..", "..", "kred-butterfly", "modular_mul_kred.v"),
                 os.path.join(HERE, "..", "..", "psi-fold-rom", "tf_rom_fold.v")]
        defines = ["-DV2"]
    else:
        srcs += [os.path.join(RTL, "top_poly_mul.v"),
                 os.path.join(RTL, "compact_bf.v"),
                 os.path.join(RTL, "modular_mul.v"),
                 os.path.join(RTL, "tf_ROM.v")]
        defines = []
    subprocess.run(["iverilog", "-g2005", "-o", out] + defines + srcs,
                   check=True)
    return out


def run(variant, x):
    sim = build(variant)
    wdir = os.path.join(HERE, "run_%s" % variant)
    os.makedirs(wdir, exist_ok=True)
    # freshness: stale dumps from an earlier run must not be able to pass
    for f in ("bank0_ntt.hex", "bank1_ntt.hex", "bank0_rt.hex", "bank1_rt.hex"):
        try:
            os.remove(os.path.join(wdir, f))
        except FileNotFoundError:
            pass
    b0, b1 = to_banks(x)
    write_hex(os.path.join(wdir, "bank0_in.hex"), b0)
    write_hex(os.path.join(wdir, "bank1_in.hex"), b1)
    r = subprocess.run(["vvp", sim], cwd=wdir, capture_output=True, text=True)
    if ("TIMEOUT" in r.stdout or r.returncode != 0
            or "NTT_DONE" not in r.stdout or "RT_DONE" not in r.stdout
            or "WARNING" in r.stdout or "ERROR" in r.stdout):
        print("FAIL: %s sim did not complete cleanly\n%s" % (variant, r.stdout[-800:]))
        sys.exit(1)
    cycles = re.findall(r"(NTT|INTT)_CYCLES=(\d+)", r.stdout)
    if sorted(m for m, _ in cycles) != ["INTT", "NTT"]:
        print("FAIL: %s sim reported cycle markers %s, expected one NTT and one INTT"
              % (variant, cycles))
        sys.exit(1)
    ntt_out = from_banks(read_hex(os.path.join(wdir, "bank0_ntt.hex")),
                         read_hex(os.path.join(wdir, "bank1_ntt.hex")))
    rt_out = from_banks(read_hex(os.path.join(wdir, "bank0_rt.hex")),
                        read_hex(os.path.join(wdir, "bank1_rt.hex")))
    return ntt_out, rt_out, dict(cycles)


def vectors():
    """Three seeded random vectors plus two edge vectors (all q-1, and an
    impulse), so a pass is not a single-input coincidence."""
    vs = []
    for seed in (0, 1, 2):
        rng = random.Random(seed)
        vs.append(("seed%d" % seed, [rng.randrange(Q) for _ in range(N)]))
    vs.append(("max", [Q - 1] * N))
    vs.append(("impulse", [1] + [0] * (N - 1)))
    return vs


def main():
    seen_cycles = {}
    for name, x in vectors():
        gold_ntt = ntt_golden(x)
        for variant in ("ref", "v2"):
            ntt_out, rt_out, cycles = run(variant, x)
            if ntt_out != gold_ntt:
                bad = next(i for i in range(N) if ntt_out[i] != gold_ntt[i])
                print("FAIL: %s/%s NTT mismatch at %d: got %d want %d"
                      % (variant, name, bad, ntt_out[bad], gold_ntt[bad]))
                sys.exit(1)
            if variant == "ref":
                want_rt = [(1024 * v) % Q for v in x]   # issue #7 at core level
                label = "2^10-scaled (bug #7 reproduced at full-core RTL)"
            else:
                want_rt = x
                label = "EXACT (fixed architecture)"
            if rt_out != want_rt:
                bad = next(i for i in range(N) if rt_out[i] != want_rt[i])
                print("FAIL: %s/%s roundtrip mismatch at %d: got %d want %d"
                      % (variant, name, bad, rt_out[bad], want_rt[bad]))
                sys.exit(1)
            # the controller has no data in its input cone: the cycle count
            # must be identical for every vector and both variants
            key = (cycles.get("NTT"), cycles.get("INTT"))
            seen_cycles.setdefault(variant, set()).add(key)
            print("ok  %-3s %-8s NTT exact; INTT(NTT(x)) %s; cycles: NTT=%s INTT=%s"
                  % (variant, name, label, key[0], key[1]))
    for variant, keys in seen_cycles.items():
        if len(keys) != 1:
            print("FAIL: %s cycle count varies with the data: %s" % (variant, sorted(keys)))
            sys.exit(1)
    (ntt_cyc, intt_cyc), = seen_cycles["ref"]
    if seen_cycles["v2"] != seen_cycles["ref"]:
        print("FAIL: v2 and ref cycle counts differ (drop-in latency broken)")
        sys.exit(1)
    # fsm_recon.v's schedule: per stage 2^9 issues at one per cycle, then
    # DRAIN reloads 16 and counts to 0 (17 edges) before the next stage or
    # done; both directions have the same shape.
    expected = LOGN * (N // 2 + 17)
    if int(ntt_cyc) != expected or int(intt_cyc) != expected:
        print("FAIL: cycle counts NTT=%s INTT=%s, expected %d = %d x (%d + 17)"
              % (ntt_cyc, intt_cyc, expected, LOGN, N // 2))
        sys.exit(1)
    print("cycles per 1024-point transform (launch to done): NTT=%s, INTT=%s "
          "(data-independent, ref == v2)" % (ntt_cyc, intt_cyc))
    print("FULLCORE SIM PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
