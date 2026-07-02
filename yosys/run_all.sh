#!/usr/bin/env bash
# Runs the whole Yosys/SymbiYosys verification suite.  Needs yosys, sby,
# yices-smt2 and python3 in PATH — e.g.:
#   nix shell nixpkgs#yosys nixpkgs#sby nixpkgs#yices --command ./run_all.sh
# or a YosysHQ oss-cad-suite environment (as in CI).
#
# MODE=bmc ./run_all.sh   runs BMC tasks only (skips the k-induction proofs;
# for these feed-forward pipelines the guarded-window BMC from unconstrained
# initial state is already a complete proof — see README.md).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${MODE:-all}"

run_sby() {
  local f="$1"; shift
  for task in "$@"; do
    if [ "$MODE" = bmc ] && [ "$task" = prove ]; then
      echo "== $f [$task] SKIPPED (MODE=bmc)"
      continue
    fi
    echo "== $f [$task]"
    sby -f "$f" "$task" | tail -1
  done
}

echo "==== leaf-unit equivalences (justify the compositional abstractions)"
run_sby fv_units.sby bmc
run_sby fv_modular_mul.sby bmc prove

echo "==== item 1: pipeline timing + function on the RTL (compositional)"
run_sby fv_compact_bf_ntt.sby bmc
run_sby fv_compact_bf_intt.sby bmc

echo "==== item 4: reset (X-robustness is item4b in audit.py)"
run_sby fv_reset.sby bmc prove

echo "==== items 3(static)+8: AGU / bank map on the RTL"
run_sby fv_agu.sby bmc prove

echo "==== item 6: parameterised-width datapath"
run_sby fv_param_width.sby bmc

echo "==== item 5: LEC (RTL vs synthesized netlist)"
yosys -q lec.ys && echo "LEC PASS (all equiv_opt -assert)"

echo "==== items 7+8+2: structural audits"
python3 audit.py

echo "ALL YOSYS CHECKS PASS"
