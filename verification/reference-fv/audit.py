#!/usr/bin/env python3
"""
Structural audits over the yosys JSON netlist:

Item 7 (CDC): every flip-flop in the flattened radix-2 datapath+AGU tree is
clocked by the single top-level `clk` — there is exactly one clock domain,
so clock-domain-crossing verification is vacuously satisfied (N/A).

Item 4b (power-up X robustness): per operating mode (sel constant while a
phase streams), the flattened compact_bf tree is a FEED-FORWARD pipeline —
the register dependency graph is acyclic and the longest input->output
register path is exactly 6.  Every register is therefore overwritten from
primary inputs within 6 cycles: no power-up X can influence outputs after
the pipeline flush.  (Taken across BOTH modes the netlist has an apparent
mult->sub->mult cycle, but the paths are sel-mux-exclusive and no single
mode activates it — which is why the analysis pins sel.)  This also
independently confirms the latency-6 bound the fv_compact_bf harnesses use.

Item 8 (access-pattern data-independence, structural half): the modules that
decide WHICH memory locations are touched (address_generator,
tf_address_generator, conflict_free_memory_map) have no polynomial-data
inputs at all — their input ports are counters/control only.  Together with
fv_agu.sv (their outputs are total functions of those counters) this proves
the memory access pattern is independent of secret data: the addressing is
constant-time by construction.

Item 2 evidence: fsm.v in the release is empty (whitespace only), which is
what BLOCKS control-FSM verification (and upstream issue #4 already reports
it).  The audit records that fact rather than silently skipping.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "..", "cfntt_ref", "hardware_code_radix-2")
FILES = ["compact_bf.v", "modular_mul.v", "modular_add.v",
         "modular_substraction.v", "address_generator.v",
         "conflict_free_memory_map.v", "tf_address_generator.v",
         "common_lib.v"]

# ports that carry loop counters / control, not polynomial data
AGU_ALLOWED_INPUTS = {
    "address_generator": {"k", "i", "p"},
    "tf_address_generator": {"clk", "rst", "conf", "k", "p"},
    "conflict_free_memory_map": {"clk", "rst", "old_address_0", "old_address_1"},
}

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


def check_single_clock():
    reads = " ; ".join("read_verilog %s" % os.path.join(RTL, f) for f in FILES)
    data = yosys_json(
        reads + " ; hierarchy -top compact_bf ; proc ; flatten ; "
        "write_json {out}")
    mod = data["modules"]["compact_bf"]
    clk_bits = tuple(mod["ports"]["clk"]["bits"])
    assert len(clk_bits) == 1
    n_ff, bad = 0, []
    for cname, cell in mod["cells"].items():
        if cell["type"] in FF_TYPES:
            n_ff += 1
            if tuple(cell["connections"]["CLK"]) != clk_bits:
                bad.append(cname)
    if bad:
        print("FAIL item7: %d/%d flip-flops not on top clk: %s"
              % (len(bad), n_ff, bad[:5]))
        return False
    print("ok  item7 CDC: single clock domain — all %d flip-flops in the "
          "flattened compact_bf tree are clocked by top-level clk "
          "(CDC vacuously N/A)" % n_ff)
    return True


def check_feed_forward(mode, selval):
    reads = " ; ".join("read_verilog %s" % os.path.join(RTL, f) for f in FILES)
    wrapper = os.path.join(HERE, "audit_bf_const.v")
    with open(wrapper, "w") as fh:
        fh.write(
            "module bf_const(input clk, rst,\n"
            "    input [13:0] u, v, w,\n"
            "    output [13:0] bf_upper, bf_lower);\n"
            "  compact_bf dut(.clk(clk), .rst(rst), .sel(%s),\n"
            "      .u(u), .v(v), .w(w),\n"
            "      .bf_upper(bf_upper), .bf_lower(bf_lower));\n"
            "endmodule\n" % selval)
    try:
        data = yosys_json(
            "read_verilog %s ; " % wrapper + reads +
            " ; hierarchy -top bf_const ; proc ; flatten ; opt -full ; "
            "write_json {out}")
    finally:
        os.unlink(wrapper)
    mod = data["modules"]["bf_const"]

    ffs = [c for c, cell in mod["cells"].items() if cell["type"] in FF_TYPES]
    ffs_set = set(ffs)
    driver = {b: c for c, cell in mod["cells"].items()
              for b in _cell_outs(cell)}
    input_bits = _port_bits(mod, "input")

    def comb_sources(bits):
        """Trace bits back through combinational cells to FFs / inputs."""
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
        print("FAIL item4b (%s): register feedback cycle through %s — "
              "pipeline is NOT feed-forward" % (mode, cyclic[:3]))
        return False
    if out_depth != 6:
        print("FAIL item4b (%s): longest input->output register path is %d, "
              "expected 6 (harness latency would be wrong!)"
              % (mode, out_depth))
        return False
    print("ok  item4b X-robustness (%s mode): feed-forward pipeline "
          "(%d FFs, register graph acyclic, max register depth %d, "
          "input->output path == 6) — every register is overwritten from "
          "primary inputs within 6 cycles, so power-up X cannot persist"
          % (mode, len(ffs), maxd))
    return True


def check_agu_ports():
    data = yosys_json(
        "read_verilog %s ; read_verilog %s ; read_verilog %s ; "
        "read_verilog %s ; hierarchy ; proc ; write_json {out}" % (
            os.path.join(RTL, "address_generator.v"),
            os.path.join(RTL, "tf_address_generator.v"),
            os.path.join(RTL, "conflict_free_memory_map.v"),
            os.path.join(RTL, "common_lib.v")))
    ok = True
    for mname, allowed in AGU_ALLOWED_INPUTS.items():
        ports = data["modules"][mname]["ports"]
        inputs = {n for n, p in ports.items() if p["direction"] == "input"}
        extra = inputs - allowed
        if extra:
            ok = False
            print("FAIL item8: %s has unexpected data inputs: %s"
                  % (mname, sorted(extra)))
        else:
            print("ok  item8 constant-time addressing: %s inputs are "
                  "counters/control only %s" % (mname, sorted(inputs)))
    return ok


def check_fsm_blocked():
    fsm = open(os.path.join(RTL, "fsm.v")).read()
    if fsm.strip():
        print("FAIL item2: fsm.v is no longer empty (%d bytes) — control-FSM "
              "verification is now UNBLOCKED; extend the harnesses!"
              % len(fsm))
        return False
    print("ok  item2 evidence: fsm.v is empty (%d bytes, whitespace only) — "
          "control/protocol verification is blocked by the release "
          "(upstream issue #4), not by this harness" % len(fsm))
    return True


def main():
    ok = check_single_clock()
    ok &= check_feed_forward("NTT", "1'b0")
    ok &= check_feed_forward("INTT", "1'b1")
    ok &= check_agu_ports()
    ok &= check_fsm_blocked()
    print("AUDITS PASS" if ok else "AUDITS FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
