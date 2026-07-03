# Proposed: CFNTT-KRED — a 1-multiplier, bug-fixed radix-2 butterfly

The result of a recursive view → implement → verify loop over the reference
design: a drop-in replacement for cfntt_ref's modular multiplier and radix-2
butterfly that

- cuts the hardware multipliers per butterfly from **3 to 1** (−67% DSPs on
  FPGA; −21% cells / −27% registers for the multiplier and −10% cells for
  the whole butterfly even in pure-LUT synthesis, see `cost_report.txt`),
- **fixes upstream issue #7** (the missing per-stage INTT halving) *inside*
  the architecture, half of it at zero multiplier cost, and
- keeps the port list, the delay fabric and the latency (4 for the
  multiplier, 6 for the butterfly) identical to the original — the FSM,
  memory banks, address generators and conflict-free mapping are untouched.

## The idea

q = 12289 = 3·2¹² + 1 is a Proth prime, so **3·2¹² ≡ −1 (mod q)** and a
28-bit product `z` reduces with shifts and adds only (K-RED, used in
*software* for this q by Longa & Naehrig 2016; the reference RTL instead
spends two extra hardware multipliers on Barrett):

```
d = 3·z[11:0] + 6q − z[27:12]        ≡ 3z (mod q),   0 < d < 2¹⁷
e = 3·d[11:0] +  q − d[16:12]        ≡ 9z (mod q),   0 < e < 2q
r = e ≥ q ? e − q : e                = 9z mod q
```

The unit therefore returns **9·a·b mod q**. The factor 9 is folded away
architecturally:

| Path | Folding | Result |
|---|---|---|
| NTT butterfly | ROM stores `W = 9⁻¹·w` (9⁻¹ = 2731) | `9·v·W = v·w` **exact** |
| INTT butterfly | the INTT twiddle is derived from the *same* ROM word by one `modular_half`: `op21(W) = (2·9)⁻¹·w` | `9·(v−u)·op21(W) = ((v−u)·w)/2` — the multiply-path **halving is fused in**, fixing issue #7 on that path for free |
| INTT add path | one `modular_half` gate (shift+add) on `u+v` | `op21(u+v)` — the other half of the fix |
| PWM (both operands data) | double-pass through the same unit with the stored constant 81⁻¹ = 11227 | `9·(9xy)·81⁻¹ = x·y` exact (costs N extra mult *cycles* per product, or a second constant port) |

The twiddle ROM keeps the exact CFNTT layout and size (N−1 words, one
shared ROM for NTT and INTT) — only its *contents* are scaled by 9⁻¹.

## Verification (all green)

| Artifact | What it proves | Status |
|---|---|---|
| `kred_math.py` | bit-exact model; `INTT(NTT(x)) == x` and `INTT(PWM(NTT a, NTT b)) == negacyclic(a,b)` on the real (9⁻¹-scaled) `tf_ROM.v` contents; kred9 vs `9c mod q` on edges + 500k samples | PASS |
| `verify_kred.py` | z3, FULL 28-bit domain, divider-free: width bounds (`0<d<2¹⁷`, `0<e<2q`), the two linear congruence identities `3c+6q = d+c₁q`, `3d+q = e+d₁q`, and the reduced output — together `r == 9c mod q` for every c | VERIFIED |
| `fv_kred.sby` | SymbiYosys, the *RTL* pipeline == the K-RED fold spec at latency 4 (BMC + k-induction), output reduced, reset clears — combined with `verify_kred.py` (fold == 9c mod q, full domain) this gives `P_out == (9·A·B) mod q` without re-bit-blasting a divider | PASS |
| `fv_bf_v2_{ntt,intt}.sby` | SymbiYosys, compositional (leaf units abstracted; justified by `fv_kred.sby` + `../yosys/fv_units.sby`): the butterfly computes exactly `(u+9vW, u−9vW)` / `(op21(u+v), 9(v−u)·op21(W))` at latency 6 through the real delay fabric | PASS |
| mutation probes | removing the add-path halving, skipping the op21-on-ROM fusion, or nudging a fold constant each makes the corresponding proof FAIL with a counterexample | non-vacuous |

## Cost (yosys generic synth, `-noabc`, flattened; `cost_report.txt`)

| Module | cells | FF bits | HW multipliers |
|---|---|---|---|
| `modular_mul.v` (reference, Barrett) | 2176 | 101 | **3** (14×14, 15×15, 14×14) |
| `modular_mul_kred.v` (proposed) | **1724 (−21%)** | **74 (−27%)** | **1** (14×14) |
| `compact_bf.v` (reference — and INTT-broken) | 2820 | 297 | 3 |
| `compact_bf_v2.v` (proposed, INTT-correct) | **2549 (−10%)** | 270 | **1** |

On FPGA the three multipliers map to DSP blocks, so the per-butterfly DSP
count drops 3 → 1; with `d` parallel butterflies the saving scales by `d`.

## The psi-fold twiddle ROM (second invention — found by VISUAL review)

Reviewing the 3D architecture model of the KRED butterfly showed the
1023-word twiddle ROM as the largest block left on the logic floorplan
(compute shrank, storage didn't), right next to two visual precedents: the
K-RED fold stages (shift-add constant multiplies are ~free) and the op21
gate on the ROM output (deriving a twiddle variant from the same stored
word already pays once).  Combining them:

**The bit-reversed negacyclic layout satisfies `w_rom[512+j] = 7·w_rom[j]
(mod q)` for ALL j (psi = kesai = 7), and ×7 = `(x<<3) − x` is shift-sub.**
So `tf_rom_fold.v` stores HALF the words (512, 9⁻¹-scaled) and derives the
upper half with `fold7` — three conditional subtractions, zero multipliers,
same interface and 1-cycle latency as `tf_ROM.v`.  The relation recurses
(`w[256+j] = 49·w[j] = fold7²`, `w[128+j] = 7⁴·w[j] = fold7⁴`, …): a
256-word ROM costs at most 3 chained fold7 gates (validated end-to-end).

| Artifact | What it proves | Status |
|---|---|---|
| `rom_fold_math.py` | fold relations (levels 1–3) against the REAL `tf_ROM.v` contents; `fold7` exhaustive over the full domain; 9⁻¹ composition; e2e round-trips with 512- and 256-word ROMs | PASS |
| `verify_rom_fold.py` | z3, full domain, divider-free: `t0 == 7x` fits 17 bits, congruence `7x == t3 + q·(4s₁+2s₂+s₃)`, `t3 < q` | VERIFIED |
| `fv_rom_fold.sby` | SymbiYosys miter: `tf_rom_fold` == the SHIPPED `tf_ROM.v` for every address (via `9·Q_new ≡ Q_ref mod q`), 1-cycle latency preserved | PASS |
| `gen_rom_fold.py` | the RTL table is generated mechanically from `tf_ROM.v` — never hand-transcribed; CI regenerates and diffs | in sync |

Measured (yosys generic synth, flattened): `tf_ROM` 7828 cells →
`tf_rom_fold` **1611 cells (−79%)**; stored bits 14322 → 7168 (−50%),
or 3584 (−75%) with the two-level variant.

(Prior art note: on-the-fly / compressed twiddle generation is a known
family of techniques; the specific bit-reversed HALF-FOLD via psi with a
Proth-prime shift-sub multiplier, composed with the 9⁻¹ K-RED scaling and
verified equivalent to the shipped ROM, is the contribution here.)

## Honesty notes

- K-RED itself is known art (Longa & Naehrig, *Speeding up the Number
  Theoretic Transform for Faster Ideal Lattice-Based Cryptography*, 2016).
  The contribution here is the **verified hardware fusion into CFNTT**: the
  single-ROM 9⁻¹-scaled twiddle scheme, the op21-on-ROM derivation that
  yields the INTT twiddle *and* the multiply-path halving in one gate, the
  81⁻¹ PWM double-pass, and end-to-end formal verification of all of it.
- PWM throughput: the double-pass costs one extra pass over N coefficients
  per polynomial product (≈ +6% total multiplier cycles for a full
  poly-mult). Alternatives (a dedicated 81⁻¹ constant multiplier, or
  folding into a final INTT stage) trade area for that latency.
- Timing: the K-RED folds are adder chains; the critical path per stage is
  comparable to the Barrett stages it replaces (three pipeline registers
  inside the reduction, same latency-4 envelope). Place-and-route numbers
  are outside this repo's scope.
