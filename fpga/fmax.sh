#!/usr/bin/env bash
# Post-route Fmax (open flow, NO Vivado) for the reference vs proposed
# multiplier and butterfly, on Artix-7 xc7a100t, via openXC7 nextpnr-xilinx.
# Each module is register-wrapped (fpga/wrap.py) so only clk + 2 pins
# are I/O and the reg-to-reg critical path is what's timed; reports the median
# of 3 seeds.
#
# Tools (pin the WORKING openXC7 tag — HEAD's flake is broken):
#   nix build github:openXC7/toolchain-nix/0.8.2#packages.x86_64-linux.nextpnr-xilinx
#   nix build github:openXC7/toolchain-nix/0.8.2#packages.x86_64-linux.nextpnr-xilinx-chipdb.artix7
# then set NP=<.../bin/nextpnr-xilinx> CHIPDB=<.../xc7a100tcsg324.bin>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
REPORTS="$here/reports"; mkdir -p "$REPORTS"   # per-seed nextpnr logs are archived here
: "${NP:?}" "${CHIPDB:?}"; YOSYS=${YOSYS:-yosys}
RTL="$root/cfntt_ref/hardware_code_radix-2"

fmax() { local top=$1; shift; local best=0 f
  local w=$(mktemp -d)
  $YOSYS -p "read_verilog $*; hierarchy -top $top; proc; write_json $w/pre.json" >/dev/null 2>&1
  python3 "$here/wrap.py" "$w/pre.json" "$top" > "$w/wrap.v"
  $YOSYS -p "read_verilog $* $w/wrap.v; synth_xilinx -flatten -top ${top}_wrap; delete t:\$scopeinfo; write_json $w/d.json" >/dev/null 2>&1
  { echo "set_property IOSTANDARD LVCMOS33 [get_ports {clk}]";
    echo "set_property IOSTANDARD LVCMOS33 [get_ports {serial_in}]";
    echo "set_property IOSTANDARD LVCMOS33 [get_ports {serial_out}]";
    echo "create_clock -period 2.0 -name clk [get_ports clk]"; } > "$w/c.xdc"
  local seeds=""
  for s in 1 2 3; do
    log="$REPORTS/${top}-seed$s.log"
    "$NP" --chipdb "$CHIPDB" --seed $s --xdc "$w/c.xdc" --json "$w/d.json" >"$log" 2>&1 \
      || { echo "nextpnr FAILED for $top seed $s (see $log)"; exit 1; }
    f=$(grep -oE "Max frequency for clock.*: [0-9.]+ MHz" "$log" | grep -oE "[0-9.]+" | tail -1)
    [ -n "$f" ] || { echo "no Fmax reported for $top seed $s (see $log)"; exit 1; }
    seeds="$seeds $f"
    awk -v a="$f" -v b="$best" 'BEGIN{exit !(a>b)}' && best=$f
  done
  printf "%-16s %6s MHz (best of 3 seeds:%s)\n" "$top" "$best" "$seeds"
  rm -rf "$w"
}
fmax modular_mul       "$RTL/modular_mul.v" "$RTL/common_lib.v"
fmax modular_mul_kred  "$root/kred-butterfly/modular_mul_kred.v"
fmax compact_bf        "$RTL/compact_bf.v" "$RTL/modular_mul.v" "$RTL/modular_add.v" "$RTL/modular_substraction.v" "$RTL/common_lib.v"
fmax compact_bf_v2     "$root/kred-butterfly/compact_bf_v2.v" "$root/kred-butterfly/modular_mul_kred.v" "$RTL/modular_add.v" "$RTL/modular_substraction.v" "$RTL/modular_half.v" "$RTL/common_lib.v"
