# newcore — our own minimal, verified NTT/INTT accelerator

A **new**, self-contained single-butterfly NTT/INTT core for Falcon
(N=1024, q=12289), built from our verified blocks but with **our own control
FSM** — so, unlike the reverse-engineered CFNTT FSM (`../proposed/fullcore/`,
which elaborates but does not round-trip), this whole core **round-trips by
construction**: `INTT(NTT(x)) == x`.

Why a fresh core: the reproducibility gap in the retrofit was the *unreleased*
CFNTT control FSM. Owning the FSM removes that gap and turns the weakness
(a core that only round-trips at the streaming/module level) into a strength
(a complete accelerator that runs end-to-end and fits a hobbyist board).

## Design (deliberately simple)

- **`compact_bf_v2`** — the 1-multiplier K-RED butterfly (latency 6), reused
  and already SMT/SbY-verified. Its INTT mode carries the per-stage `1/2`, so
  the transform round-trips to `x` (the released core's bug is absent).
- **`tf_rom_fold`** — the ψ-fold twiddle ROM (stores half the words).
- **`ntt_ram`** — one dual-port BRAM (1024×14 → 1×RAMB18) holding the
  coefficients; host port for load/read while idle.
- **own FSM** — nested loops `p`(stage)/`k`(group)/`j`(butterfly), one
  butterfly at a time (sequential → a single dual-port BRAM suffices, and
  correctness is easy to see and verify). Schedule proven equivalent to the
  golden streaming harness `../proposed/fullcore/tb_stream.v`.

`start`+`mode` (0=NTT, 1=INTT) runs a transform on the RAM contents; `done`
pulses when finished.

## Status

- **Functional round-trip: PASS** — `tb_ntt_core.v` loads `x`, runs NTT then
  INTT, and checks `INTT(NTT(x)) == x` for all 1024 coefficients under
  iverilog.
- **NTT cross-validation: PASS** — the post-NTT memory is bit-identical to the
  golden streaming harness (`../proposed/fullcore/tb_stream.v`) on the same
  input, so the core computes the *correct* NTT, not merely an invertible one.
  Both checks: `python3 newcore/run_check.py` (exit 0 iff both pass).
- **Synthesis (yosys `synth_xilinx`, Artix-7):** **1 DSP48**, **1 RAMB18**,
  ~186 FF, ~600 LUT — fits **Basys 3** (`xc7a35t`: 90 DSP / 50 BRAM / 20.8k
  LUT) with vast headroom.

## Run

```sh
RTL="../proposed/kred/compact_bf_v2.v ../proposed/kred/modular_mul_kred.v \
     ../proposed/rom-fold/tf_rom_fold.v \
     ../cfntt_ref/hardware_code_radix-2/modular_add.v \
     ../cfntt_ref/hardware_code_radix-2/modular_substraction.v \
     ../cfntt_ref/hardware_code_radix-2/modular_half.v \
     ../cfntt_ref/hardware_code_radix-2/common_lib.v"
iverilog -g2012 -o /tmp/ntt.vvp ntt_core.v tb_ntt_core.v $RTL && vvp /tmp/ntt.vvp
```

## Next (in progress)

1. Formal check of the FSM (BMC: `busy`/`done` handshake, address bounds).
2. openXC7 bitstream + a **Basys 3** self-test wrapper (LFSR stimulus →
   round-trip → PASS on an LED / 7-seg), XDC for `xc7a35tcpg236`.
3. Optional throughput: pipeline within a stage (2-bank conflict-free) for
   ~1 butterfly/cycle.
