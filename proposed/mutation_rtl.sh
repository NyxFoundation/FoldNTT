#!/usr/bin/env bash
# Non-vacuity harness for the PROPOSED RTL proofs: inject a realistic bug
# into each Verilog module and assert the corresponding SymbiYosys harness
# FAILS with a counterexample.  A proof that passes on the real RTL is only
# meaningful if it fails on a wrong one.
set -u
cd "$(dirname "$0")"
fails=0

mutate() { # file, sed-expr, harness-dir, sby-file, task, label
  local f=$1 expr=$2 dir=$3 sby=$4 task=$5 label=$6
  cp "$f" "$f.orig"
  sed -i "$expr" "$f"
  if cmp -s "$f" "$f.orig"; then
    echo "HARNESS BUG: mutation did not apply — $label"; fails=$((fails+1))
    rm "$f.orig"; return
  fi
  if (cd "$dir" && sby -f "$sby" "$task" >/dev/null 2>&1); then
    echo "MISSED  $label (proof still passes on mutated RTL!)"; fails=$((fails+1))
  else
    echo "ok      $label"
  fi
  mv "$f.orig" "$f"
}

mutate kred/modular_mul_kred.v "s/17'd73734/17'd73733/" \
  kred fv_kred.sby bmc "M1 kred fold offset 6q-1        -> fv_kred FAILs"
mutate kred/compact_bf_v2.v "s/assign add_sel = sel == 1'b0 ? add_out : add_half;/assign add_sel = add_out;/" \
  kred fv_bf_v2_intt.sby bmc "M2 drop add-path halving        -> fv_bf_v2_intt FAILs"
mutate kred/compact_bf_v2.v "s/assign mux_out4 = sel == 1'b0 ? w_q1 : w_half;/assign mux_out4 = sel == 1'b0 ? w_q1 : w_q2;/" \
  kred fv_bf_v2_intt.sby bmc "M3 skip op21-on-ROM twiddle     -> fv_bf_v2_intt FAILs"
mutate rom-fold/tf_rom_fold.v "s/9'd7: base <= 14'd3638;/9'd7: base <= 14'd3639;/;s/9'd7: base <= 14'd3637;/9'd7: base <= 14'd3638;/" \
  rom-fold fv_rom_fold.sby bmc "M4 corrupt one stored ROM word  -> fv_rom_fold FAILs"
mutate rom-fold/tf_rom_fold.v "s/{base, 3'b000}/{1'b0, base, 2'b00}/" \
  rom-fold fv_rom_fold.sby bmc "M5 fold7 shift 3 -> 2 (3x not 7x) -> fv_rom_fold FAILs"

# restore any stale sby workdirs left by mutated runs
rm -rf kred/fv_kred_bmc kred/fv_bf_v2_intt_bmc rom-fold/fv_rom_fold_bmc
if [ "$fails" -eq 0 ]; then echo "ALL RTL MUTATIONS DETECTED"; else echo "MUTATION SWEEP FAILED ($fails)"; exit 1; fi
