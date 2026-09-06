# Full-core / system-level RTL evidence

The module-level proofs (`../../kred-butterfly/`, `../../psi-fold-rom/`) establish each invented
block correct for all inputs. This folder raises that to the transform level
under a real Verilog simulator.

## What runs (`run_stream.py` — CI)

`tb_stream.v` drives the invented RTL (the register-level hardware source
code: `compact_bf_v2` +
`modular_mul_kred` + `tf_rom_fold`) through a complete N=1024 DIT-NR NTT and
DIF-RN INTT under iverilog, one butterfly (the transform's small
multiply-and-add step) per cycle (pipelined; results
collected via an index delay line: butterflies within a stage touch
disjoint indices, so back-to-back issue has no RAW hazard, and the pipeline
is drained between stages). The whole folded ROM is pre-read into `wrom[]`
first, exercising `tf_rom_fold` across its full address range.

Checks, on multiple random vectors:

- `NTT(x)` == the reference `DIT_NR_NTT` on the real twiddle table, and
- `INTT(NTT(x)) == x` exactly, i.e. the issue-#7 halving fix works at
  the full-transform level, not just per butterfly.

```
nix shell nixpkgs#iverilog --command uv run run_stream.py   # -> STREAM SIM PASS
```

This is orthogonal to cfntt_ref's banked-memory schedule: the inventions are
drop-in (same ports, same latency), so a correct controller sequences them
into a correct transform regardless of the conflict-free memory mapping.

## Reconstructed banked FSM (`fsm_recon.v`, `tb_fullcore.v`): working

The released `fsm.v` is empty (upstream issue #4), so the shipped
`top_poly_mul` cannot elaborate as-is. `fsm_recon.v` is a reconstructed
controller with the exact port list `top_poly_mul` instantiates, and
`top_poly_mul_v2.v` swaps in the invented modules. This drives the actual
banked datapath (two conflict-free banks, address generators,
`network_bf_in/out`), which additionally exercises the memory system.

Status: cycle-exact against the shipped datapath. `run_sim.py` runs the
reference core (shipped `compact_bf` + `tf_ROM`) and the v2 core through a
full NTT then INTT on five vectors (three seeded random, all-(q−1), impulse):

- reference: `NTT(x)` equals the golden DIT_NR_NTT exactly, and
  `INTT(NTT(x)) = 2¹⁰·x` — upstream issue #7 reproduced at full-core RTL;
- v2: `NTT(x)` exact and `INTT(NTT(x)) = x` exact;
- 5290 cycles per 1024-point transform, launch to `done` (10 stages ×
  (512 issues at one butterfly per cycle + 17 cycles of drain and
  turnaround)), identical for every vector and for both cores
  (asserted: the controller has no data in its input cone, and the
  retrofit is latency-identical). The host must hold `conf` until
  `done_flag` rises: the shipped `tf_address_generator` decodes it live.

Schedule (derived from the shipped datapath's own timing, see the header of
`fsm_recon.v`): issue at t → registered bank/tf addresses at t+1 → bank Q,
`network_bf_in` and ROM Q aligned at t+2 → butterfly latency 6 → output,
write-side select (`shift_7`) and write address (`shift_7`) at t+8, so
`wen = pipe[7]`. Two earlier defects hid behind each other: `wen` sat at
`pipe[9]` (which skipped each stage's first two writes and wrote back a
phantom butterfly on the (0, 2^p) pair at the end of each stage), and the
testbench preloaded the banks with `$readmemh` in a posedge time step,
racing `data_bank`'s per-cycle `bank[A1] <= bank[A1]` refresh and leaving
address 0 of both banks X. The preload now happens on a negedge.

This is a controller consistent with the released datapath, not the
authors' original: the unreleased FSM's timed behaviour stays unknowable,
and the reference paper's cycle counts are not reproduced here.

## Files

| File | Role |
|---|---|
| `tb_stream.v`, `run_stream.py` | pipelined full-transform harness over the invented RTL (the working, CI-run evidence) |
| `fsm_recon.v` | reconstructed control FSM (port-compatible with `top_poly_mul`; cycle-exact against the shipped datapath) |
| `top_poly_mul_v2.v` | shipped top with `compact_bf_v2` + `tf_rom_fold` swapped in |
| `tb_fullcore.v`, `run_sim.py` | banked-core testbench + driver (ref reproduces #7, v2 exact, five vectors, cycle counts asserted; CI-run) |
