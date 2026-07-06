# Scaling: what the 3→1 DSP saving buys under parallel instantiation

The paper's single-BFU core is deliberately minimal. This note asks the
next question: if you spend the saving on parallel butterfly lanes, how
much performance does one chip buy, and where is the ceiling? Numbers
here are measured with `fpga/scale_sweep.sh` unless marked as estimates;
none of this is in the paper's claim set.

## Method

`fpga/scale_sweep.sh` synthesizes a *lane array*: d butterflies, each
with its own twiddle ROM, fed from a shift register, outputs reduced
through a two-stage registered XOR so the harness never owns the
critical path (an earlier single-stage XOR tree did, and cost ~20 MHz —
kept in the git history as a cautionary tale). Two variants:

- **ref**: reference `compact_bf` (Barrett, 3 DSP) + full `tf_ROM`
- **kred**: `compact_bf_v2` (K-RED, 1 DSP) + ψ-fold `tf_rom_fold`

The probe measures how the *arithmetic* scales. It deliberately excludes
the banked memory system, address generators and lane-to-bank
permutation network a full d-lane core needs; those add area to both
variants and their wiring pressure grows with d.

## Measured: area scales linearly, and the LUT cost per lane is a wash

yosys `synth_xilinx` (Artix-7 primitives):

| variant | d | LUT | FF | DSP | CARRY4 |
|---|---|---|---|---|---|
| kred | 16 | 6,876 | 2,946 | 16 | 960 |
| kred | 64 | 27,265 | 11,778 | 64 | 3,840 |
| kred | 128 | 52,870 | 23,554 | 128 | 7,680 |
| kred | 240 | 98,398 | 44,162 | 240 | 14,400 |
| ref | 16 | 6,917 | 2,898 | 48 | 384 |
| ref | 64 | 27,785 | 11,586 | 192 | 1,536 |
| ref | 80 | 34,579 | 14,482 | 240 | 1,920 |

Two facts fall out:

1. **Linear**: per-lane cost is essentially constant from d=16 to d=240
   (kred 410–430 LUT/lane, ref ~432 LUT/lane); no superlinear glue in
   the arithmetic itself.
2. **The LUT premium of K-RED is zero — slightly negative.** The
   butterfly alone costs more LUTs than Barrett's (231 vs 158), but the
   ψ-fold ROM gives back more than the difference (192 vs 241): a full
   kred lane is a few percent *cheaper* in LUTs than a ref lane, at one
   third the DSPs. The 3→1 DSP saving is not bought with fabric. The
   trade that remains: kred lanes carry ~7× the CARRY4 chains
   (shift-add adders), which is where routing pressure would appear.

## Measured: post-route clock at equal lane count

openXC7 nextpnr-xilinx, xc7a100t, one seed, 2.0 ns target:

| variant | d | DSP util | LUT util | post-route Fmax |
|---|---|---|---|---|
| kred | 32 | 13% | 22% | 69.2 MHz |
| ref | 32 | 40% | 22% | 74.1 MHz |
| kred | 64 | 27% | 43% | 67.8 MHz |
| kred | 128 | 53% | 83% | (routing at the time of writing; appended below when done) |
| ref | 64 | 80% | 44% | **did not converge**: 15 h of placement without a result |

Three observations:

- **At equal lane count, Barrett clocks ~7% faster** (74.1 vs
  69.2 MHz at d=32). The module-level gap was −26% in isolation; in a
  lane array it shrinks to ~7%, and in the full single-BFU core it was
  ~1%. So the clock price of K-RED depends on how much else surrounds
  the butterfly, and at farm scale it is small against the 3× DSP
  saving.
- **kred's congestion behaviour is graceful so far**: 69.2 → 67.8 MHz
  (−2%) from d=32 to d=64 despite the CARRY4 density.
- **Dense DSP placement is the open flow's weak spot**: ref at d=64
  (192 of 240 DSPs, 80%) never finished placement in 15 hours. That is
  a statement about nextpnr-xilinx's placer, not about the Barrett
  design, but it is operationally real if the open flow is your
  toolchain: with K-RED the same 64 lanes are a routine 27%-DSP build.

Absolute farm frequencies (~68–74 MHz) sit below the isolated-module
Fmax (~122–164 MHz) because the harness loads every lane from one giant
shift register with a shared select; use the *relative* numbers.

## Iso-chip lane budgets

With measured per-lane costs, the lane count a device supports is
`min(DSP budget, usable-LUT budget)`; we assume 80% of LUTs are usable
by lanes (the rest for the memory system this probe excludes):

| device | LUT / DSP | ref lanes (DSP-bound) | kred lanes | lane ratio | DSPs left over (kred) |
|---|---|---|---|---|---|
| xc7a35t | 20.8k / 90 | 30 | ~39 (LUT-bound) | 1.3× | 51 |
| xc7a100t | 63.4k / 240 | 80 | ~120 (LUT-bound) | 1.5× | 120 |
| xc7a200t | 134.6k / 740 | ~246 | ~254 (LUT-bound) | ~1.0× | ~486 |

The honest reading: **the retrofit converts the binding resource from
DSP to LUT.** On a standalone Artix part the lane-count gain is
1.0–1.5×, *and* half to two-thirds of the device's DSPs stay free. The
full 3× materializes exactly when DSPs are the contended resource — a
DSP-poor device, or the realistic case where the NTT shares the chip
with other DSP-hungry logic (an FHE accelerator's multipliers, filters,
anything). In every case the freed DSPs are the fungible currency; the
lane ratio is what a dedicated-chip benchmark would see.

Putting lanes and clocks together for xc7a100t (5,120 butterflies per
1024-point NTT, 1 butterfly/lane/cycle; farm clocks, so shapes not
absolutes): ref at 80 lanes and ~74 MHz gives 64 cycles ≈ 0.86 µs/NTT;
kred at 120 lanes and ~68 MHz gives ~43 cycles ≈ 0.63 µs/NTT — about
**1.4× the transforms per second per chip, with 120 DSPs still free**.

## The ceiling

Parallelism inside one transform is capped by the stage width:
N/2 = 512 butterflies for N = 1024. Beyond that, unroll the 10 stages
into a pipeline (one transform per cycle in steady state): 5,120
butterflies in flight, i.e. **5,120 DSPs for K-RED vs 15,360 for
Barrett**. The largest current devices carry ~14k DSPs, so the fully
unrolled Falcon NTT fits on one chip with K-RED and does not with
Barrett (estimate from device datasheets, not synthesized). That is the
general shape of the answer: every scaling ceiling — stage width, chip
DSP budget, board count — sits 3× further away in the resource NTT
accelerators are usually bound by.

## Reproduce

```sh
# area sweep (minutes)
nix shell nixpkgs#yosys --command fpga/scale_sweep.sh
# post-route Fmax points (tens of minutes each; PNR_SET picks points)
DO_PNR=1 NP=<nextpnr-xilinx> CHIPDB=<xc7a100tcsg324.bin> fpga/scale_sweep.sh
```

Caveats: lane arrays without the banked memory network (its wiring cost
grows with d and hits both variants); one PnR seed; open-flow timing
model (see the paper §6's hedge); the 80%-usable-LUT assumption; ROMs
map to distributed LUT-ROM at this size, so BRAM counts are zero in the
probe.
