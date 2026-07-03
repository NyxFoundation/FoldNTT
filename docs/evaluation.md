# Evaluation (Phase 3–4)

## §sim — system-level RTL simulation (DONE)

`proposed/fullcore/run_stream.py` drives the **real invented RTL**
(`compact_bf_v2` + `modular_mul_kred` + `tf_rom_fold`) through a full N=1024
NTT and INTT under iverilog. Result: on every tested vector, the RTL
`NTT(x)` equals the reference `DIT_NR_NTT` on the real twiddle table, and
`INTT(NTT(x)) == x` **exactly** — the issue-#7 halving fix and the
9⁻¹-scaled folded ROM compose into a correct transform at the system level,
not merely per butterfly.

This closes the gap the module proofs leave: fv_bf_v2 proves the butterfly
== spec for every input; `run_stream.py` shows the specced modules,
sequenced by a controller and fed by the folded ROM, realize the whole
transform on real gates (iverilog).

Caveat (honest): cfntt_ref's *exact* banked-memory schedule is not
reproduced — the released `fsm.v` is empty (upstream #4). A reconstructed
FSM (`fsm_recon.v`) driving the banked datapath is included but not yet
cycle-accurate; it is future work and off the critical path, since the
inventions are drop-in with identical latency. See
`proposed/fullcore/README.md`.

## §synth — synthesis cost (DONE, generic; PnR pending)

All numbers from `yosys` generic synthesis (`synth -flatten -noabc`),
reproducible via `proposed/kred/cost_report.ys` and the ROM comparison. Cell
counts are technology-independent gate counts, not LUTs.

| Block | reference | proposed | Δ |
|---|---|---|---|
| modular multiplier | `modular_mul.v` 2176 cells, 101 FF, **3 mults** | `modular_mul_kred.v` 1724 cells, 74 FF, **1 mult** | −21% cells, −27% FF, −67% mults |
| butterfly | `compact_bf.v` 2820 cells, 297 FF, 3 mults | `compact_bf_v2.v` 2549 cells, 270 FF, 1 mult | −10% cells (**and INTT-correct**) |
| twiddle ROM | `tf_ROM.v` 7828 cells, 14322 stored bits | `tf_rom_fold.v` 1611 cells, 7168 stored bits | −79% cells, −50% bits |

On FPGA the three multipliers map to DSP48 blocks, so the per-butterfly DSP
count is 3 → 1; with `d` parallel butterflies the DSP saving is ×d. The ROM
maps to BRAM/distributed-RAM — halving the stored bits is a direct BRAM/LUT
saving, recursively −75% with the two-level fold.

### PnR (TODO before submission)

The generic cell counts are directionally strong but a reviewer will want
**Vivado LUT/FF/DSP/BRAM + Fmax** on the same part CFNTT used (Artix-7),
v1 vs v2, to confirm (a) fold7 closes timing on the ROM output path, (b) the
K-RED adder chains don't lengthen the critical path vs the Barrett stages
they replace. Open-flow alternative: `yosys synth_xilinx` + `nextpnr-xilinx`
(openXC7) for a first Fmax estimate. Blocked on a synthesizable full core
(the FSM reconstruction) for whole-core numbers; per-module PnR is doable now.

## Reproducibility

Every number above regenerates from the public repo:
- `proposed/run_all.sh` — all module proofs + audits + mutation sweep
- `proposed/fullcore/run_stream.py` — the system-level simulation
- `proposed/kred/cost_report.ys` — the synthesis cost report
CI (`.github/workflows/verify.yml`) runs the proof/audit/sim suite on every push.
