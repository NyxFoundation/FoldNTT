# Full-core / system-level RTL evidence

The module-level proofs (`../kred/`, `../rom-fold/`) establish each invented
block correct for all inputs. This folder raises that to the transform level
under a real Verilog simulator.

## What runs (`run_stream.py` — CI)

`tb_stream.v` drives the **real invented RTL** (`compact_bf_v2` +
`modular_mul_kred` + `tf_rom_fold`) through a complete N=1024 DIT-NR NTT and
DIF-RN INTT under iverilog, one butterfly per cycle (pipelined; results
collected via an index delay line — butterflies within a stage touch
disjoint indices, so back-to-back issue has no RAW hazard, and the pipeline
is drained between stages). The whole folded ROM is pre-read into `wrom[]`
first, exercising `tf_rom_fold` across its full address range.

Checks, on multiple random vectors:

- `NTT(x)` == the reference `DIT_NR_NTT` on the real twiddle table, and
- `INTT(NTT(x)) == x` **exactly** — i.e. the issue-#7 halving fix works at
  the full-transform level, not just per butterfly.

```
nix shell nixpkgs#iverilog --command uv run run_stream.py   # -> STREAM SIM PASS
```

This is orthogonal to cfntt_ref's banked-memory schedule: the inventions are
drop-in (same ports, same latency), so a correct controller sequences them
into a correct transform regardless of the conflict-free memory mapping.

## Reconstructed banked FSM (`fsm_recon.v`, `tb_fullcore.v`) — future work

The released `fsm.v` is **empty** (upstream issue #4), so the shipped
`top_poly_mul` cannot elaborate as-is. `fsm_recon.v` is a reconstructed
controller with the exact port list `top_poly_mul` instantiates, and
`top_poly_mul_v2.v` swaps in the invented modules. This drives the *actual
banked datapath* (two conflict-free banks, address generators,
`network_bf_in/out`), which additionally exercises the memory system.

Status: **the reconstructed schedule does not yet match the shipped
datapath's exact pipeline timing** — some bank cells are written before the
pipeline fills, leaving X's after the transform. A faithful cycle-accurate
reconstruction of an unreleased FSM is a research task in its own right and
is left as future work; it is **not** on the critical path for the
inventions' correctness, which the streaming harness above establishes at
the transform level and the SymbiYosys proofs establish per module. The
files are kept so the reconstruction can be finished later.

## Files

| File | Role |
|---|---|
| `tb_stream.v`, `run_stream.py` | pipelined full-transform harness over the invented RTL (the working, CI-run evidence) |
| `fsm_recon.v` | reconstructed control FSM (port-compatible with `top_poly_mul`) — schedule not yet cycle-exact |
| `top_poly_mul_v2.v` | shipped top with `compact_bf_v2` + `tf_rom_fold` swapped in |
| `tb_fullcore.v` | banked-core testbench (NTT then INTT, bank dumps) — pending the FSM reconstruction |
