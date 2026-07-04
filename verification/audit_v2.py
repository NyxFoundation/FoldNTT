#!/usr/bin/env python3
"""
Structural audits for the PROPOSED RTL (compact_bf_v2 + modular_mul_kred +
tf_rom_fold) — the analogue of ../yosys/audit.py items 4b/7 applied to the
inventions, plus a structural lint:

  lint : yosys `check -assert` on every proposed module (no combinational
         loops, no conflicting drivers, no dangling wires that matter).
  4b   : per operating mode (sel constant), the flattened compact_bf_v2
         tree is a FEED-FORWARD pipeline — register graph acyclic and the
         longest input->output register path is EXACTLY 6, confirming the
         latency the fv_bf_v2 harnesses assert (now with the 4-stage K-RED
         pipeline inside).
  7    : single clock domain — every flip-flop in the flattened v2 tree
         (and in tf_rom_fold) is clocked by the top-level clk.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "cfntt_ref", "hardware_code_radix-2")

V2_FILES = [
    os.path.join(HERE, "..", "kred-butterfly", "compact_bf_v2.v"),
    os.path.join(HERE, "..", "kred-butterfly", "modular_mul_kred.v"),
    os.path.join(RTL, "modular_add.v"),
    os.path.join(RTL, "modular_substraction.v"),
    os.path.join(RTL, "modular_half.v"),
    os.path.join(RTL, "common_lib.v"),
]
ROM_FILES = [os.path.join(HERE, "..", "psi-fold-rom", "tf_rom_fold.v")]

FF_TYPES = {"$dff", "$adff", "$sdff", "$dffe", "$adffe", "$sdffe"}


def yosys_json(script):
    out = os.path.join(HERE, "audit_out.json")
    subprocess.run(["yosys", "-q", "-p", script.format(out=out)],
                   check=True, cwd=HERE)
    with open(out) as fh:
        data = json.load(fh)
    os.unlink(out)
    return data


def _cell_ins(cell):
    dirs = cell.get("port_directions", {})
    return [b for pname, conn in cell["connections"].items()
            if dirs.get(pname, "input") == "input"
            for b in conn if isinstance(b, int)]


def _cell_outs(cell):
    dirs = cell.get("port_directions", {})
    return [b for pname, conn in cell["connections"].items()
            if dirs.get(pname) == "output"
            for b in conn if isinstance(b, int)]


def _port_bits(mod, direction):
    return {b for port in mod["ports"].values()
            if port["direction"] == direction
            for b in port["bits"] if isinstance(b, int)}


def check_lint():
    """yosys `check -assert` per proposed module."""
    ok = True
    for top, files in (("compact_bf_v2", V2_FILES),
                       ("modular_mul_kred", V2_FILES[1:2]),
                       ("tf_rom_fold", ROM_FILES)):
        reads = " ; ".join("read_verilog %s" % f for f in files)
        r = subprocess.run(
            ["yosys", "-q", "-p",
             "%s ; hierarchy -top %s ; proc ; check -assert" % (reads, top)],
            cwd=HERE)
        if r.returncode != 0:
            ok = False
            print("FAIL lint: yosys check -assert failed for %s" % top)
        else:
            print("ok  lint: %s — no comb loops / conflicting drivers" % top)
    return ok


def check_feed_forward(mode, selval):
    reads = " ; ".join("read_verilog %s" % f for f in V2_FILES)
    wrapper = os.path.join(HERE, "audit_bf2_const.v")
    with open(wrapper, "w") as fh:
        fh.write(
            "module bf2_const(input clk, rst,\n"
            "    input [13:0] u, v, w,\n"
            "    output [13:0] bf_upper, bf_lower);\n"
            "  compact_bf_v2 dut(.clk(clk), .rst(rst), .sel(%s),\n"
            "      .u(u), .v(v), .w(w),\n"
            "      .bf_upper(bf_upper), .bf_lower(bf_lower));\n"
            "endmodule\n" % selval)
    try:
        data = yosys_json(
            "read_verilog %s ; " % wrapper + reads +
            " ; hierarchy -top bf2_const ; proc ; flatten ; opt -full ; "
            "write_json {out}")
    finally:
        os.unlink(wrapper)
    mod = data["modules"]["bf2_const"]

    ffs = [c for c, cell in mod["cells"].items() if cell["type"] in FF_TYPES]
    ffs_set = set(ffs)
    driver = {b: c for c, cell in mod["cells"].items()
              for b in _cell_outs(cell)}
    input_bits = _port_bits(mod, "input")

    def comb_sources(bits):
        srcs, seen, work = set(), set(), list(bits)
        while work:
            b = work.pop()
            if b in seen:
                continue
            seen.add(b)
            if b in input_bits:
                srcs.add("$input")
            elif b in driver:
                c = driver[b]
                if c in ffs_set:
                    srcs.add(c)
                else:
                    work += _cell_ins(mod["cells"][c])
        return srcs

    ff_deps = {f: comb_sources(_cell_ins(mod["cells"][f])) for f in ffs}
    depth, on_stack, cyclic = {}, set(), []

    def dfs(f):
        if f == "$input":
            return 0
        if f in depth:
            return depth[f]
        if f in on_stack:
            cyclic.append(f)
            return 0
        on_stack.add(f)
        d = 1 + max((dfs(s) for s in ff_deps[f]), default=0)
        on_stack.discard(f)
        depth[f] = d
        return d

    maxd = max((dfs(f) for f in ffs), default=0)
    out_depth = max((dfs(s) for s in comb_sources(_port_bits(mod, "output"))
                     if s != "$input"), default=0)
    if cyclic:
        print("FAIL item4b (%s): register feedback cycle through %s"
              % (mode, cyclic[:3]))
        return False
    if out_depth != 6:
        print("FAIL item4b (%s): input->output register path is %d, "
              "expected 6 (fv_bf_v2 latency would be wrong!)"
              % (mode, out_depth))
        return False
    print("ok  item4b (%s mode): compact_bf_v2 tree is feed-forward "
          "(%d FFs, acyclic, max register depth %d, input->output path == 6 "
          "— the fv_bf_v2 latency assumption is confirmed structurally)"
          % (mode, len(ffs), maxd))
    return True


def check_single_clock():
    ok = True
    for label, top, files in (
            ("compact_bf_v2", "compact_bf_v2", V2_FILES),
            ("tf_rom_fold", "tf_rom_fold", ROM_FILES)):
        reads = " ; ".join("read_verilog %s" % f for f in files)
        data = yosys_json(
            reads + " ; hierarchy -top %s ; proc ; flatten ; "
            "write_json {out}" % top)
        mod = data["modules"][top]
        clk_bits = tuple(mod["ports"]["clk"]["bits"])
        bad, n_ff = [], 0
        for cname, cell in mod["cells"].items():
            if cell["type"] in FF_TYPES:
                n_ff += 1
                if tuple(cell["connections"]["CLK"]) != clk_bits:
                    bad.append(cname)
        if bad:
            ok = False
            print("FAIL item7: %s has %d flip-flops off the top clk"
                  % (label, len(bad)))
        else:
            print("ok  item7: %s — all %d flip-flops on top-level clk "
                  "(single clock domain)" % (label, n_ff))
    return ok


def main():
    ok = check_lint()
    ok &= check_feed_forward("NTT", "1'b0")
    ok &= check_feed_forward("INTT", "1'b1")
    ok &= check_single_clock()
    print("AUDITS PASS" if ok else "AUDITS FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
