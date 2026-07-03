---
title: "Verified, Multiplier-Lean NTT Hardware for Proth Primes: a Formally-Checked Retrofit of a Conflict-Free Accelerator (with a Bug Found Along the Way)"
author: NyxFoundation
date: 2026
abstract: |
  We present a formally verified redesign of the released radix-2 CFNTT
  number-theoretic-transform accelerator (TCHES 2022), for the Falcon /
  FN-DSA prime q = 12289. Three results. (1) A *drop-in* K-RED reduction
  butterfly that replaces the reference's three hardware multipliers with
  one, exploiting q = 3·2¹²+1's Proth structure; the spurious scaling is
  folded into the twiddle ROM, and the same fold *fixes a functional bug we
  found in the released RTL* — its inverse transform omits a per-stage
  halving and is scaled by 2¹⁰ (reported upstream). (2) A ψ-fold twiddle
  ROM that stores half the words (recursively a quarter) and derives the
  rest with a shift-add gate, exploiting the bit-reversed negacyclic
  layout's symmetry `w[N/2+j] = ψ·w[j]` — distinct from the negation
  symmetry used by prior half-memory generators, which is structurally
  unavailable here. (3) An end-to-end *functional* verification methodology
  — exact-width SMT with a divider-free congruence encoding, compositional
  assume-guarantee, BMC-completeness for pipeline properties, and
  mutation-tested non-vacuity — reproducible in CI, which is how the bug
  surfaced. A parameterized generator instantiates all of this for any
  Proth NTT prime; we validate Kyber / ML-KEM (q = 3329) exhaustively as a
  second instance. Measured on the reference design: multiplier −21% cells
  / 3→1 DSP, butterfly −10% cells while becoming inverse-correct, twiddle
  ROM −79% cells / −50% stored bits.
---

<!-- Working draft (Phase 7). Numbers and claims trace to docs/*.md and the
     repository's CI-reproducible scripts. TODOs are marked inline. -->

# 1. Introduction

Lattice-based post-quantum schemes — Kyber/ML-KEM, Dilithium/ML-DSA,
Falcon/FN-DSA — spend most of their cycles in polynomial multiplication,
which hardware accelerates with the number-theoretic transform (NTT). The
NTT's cost is dominated by two resources: **modular multipliers** (in the
butterflies) and **twiddle-factor storage** (the ROM of roots of unity).
Reducing either, without changing the surrounding memory system or control,
is directly valuable.

We start from a concrete, peer-reviewed artifact: the CFNTT accelerator
[CFNTT, TCHES 2022], whose contribution is a conflict-free memory mapping
for an in-place radix-2/4 NTT, released as open RTL. Working from its real
source, we make three contributions.

- **A verified 1-multiplier butterfly (§4.1).** For q = 12289 = 3·2¹²+1 (a
  Proth prime, and Falcon's modulus), the reference's Barrett reduction
  spends two hardware multipliers beyond the unavoidable product. We replace
  them with shift-add **K-RED** folds — one multiplier total — and fold the
  resulting constant factor into the twiddle ROM. The same fold repairs a
  **bug we found** in the released inverse transform (§3).

- **A ψ-fold twiddle ROM (§4.2), found by visual review.** The bit-reversed
  negacyclic table obeys `w[N/2+j] = ψ·w[j]`; with ψ shift-friendly (Falcon
  ψ=7), half the ROM is derived by a shift-sub gate. This halves (recursively
  quarters) the stored words. The relation is distinct from the negation
  symmetry used by prior half-memory twiddle generators, which does not
  apply to bit-reversed tables.

- **A functional-verification methodology (§5)** that checks the *arithmetic
  and datapath against a mathematical specification* — as opposed to the
  masking/side-channel focus of recent PQC-hardware verification — down to
  the shipped ROM contents, reproducibly in CI. This is not incidental: the
  inverse-transform bug surfaced *because* we verified rather than tested.

We show all three are instances of a construction that generalizes to any
Proth NTT prime, with a generator that emits and checks per-prime RTL
(§6), validated on Kyber (q = 3329) exhaustively. §7 reports costs.

**Provenance (one honest paragraph).** The ψ-fold ROM was discovered by an
LLM coding agent while *visually reviewing a 3D floor-plan model* of the
architecture inside an automated view→implement→verify loop: with the
arithmetic shrunk by the K-RED step, the twiddle ROM was visibly the largest
remaining block, adjacent to shift-add fold stages and a reuse gate that
suggested the derivation. We report this because it is true and reproducible
(the full derivation history is public), not as a methodological claim; the
mathematics and proofs stand on their own.

# 2. Background

**NTT and the CFNTT accelerator.** [TODO: 1 paragraph — negacyclic NTT for
polynomial multiplication in Z_q[x]/(x^N+1); DIT-NR forward / DIF-RN inverse
butterflies; ψ the 2N-th root; CFNTT's conflict-free 2-bank parity mapping,
address generators, single shared twiddle ROM. Cite CFNTT.]

**Modular reduction.** Barrett and Montgomery are the general-purpose
choices. For Proth primes q = k·2^m+1, K-RED [Longa–Naehrig 2016] reduces
with shifts and adds; it is established in *software* NTTs and, more
recently, in Kyber *hardware* [cite the K-RED-Shift / Proth-l line]. Our use
is a *verified retrofit into a conflict-free accelerator*, with the factor
folded into the ROM and reused to fix the inverse transform.

**Twiddle storage.** Prior work reduces the ROM by on-the-fly generation
(a modular multiplier per butterfly) or by a *half-memory* generator using
the negation symmetry `W^{N/2} = −1` [cite]. We show a different symmetry,
specific to the bit-reversed negacyclic layout, that is multiplier-free.

**Verified PQC hardware.** The 2026 wave targets masking composition and
side-channel leakage [cite the masked-NTT / PINI line]. Functional
correctness of the arithmetic against a spec — our axis — is comparatively
underserved, and is what exposes logic bugs like the one in §3.

# 3. A bug in the released inverse transform

The DIF-RN inverse butterfly must apply a ½ scaling per stage (paper Alg. 3;
the reference Python model applies `op21`). The released radix-2 RTL ships
`modular_half.v` but **instantiates it nowhere** in `compact_bf.v`; the
radix-4 PEs do instantiate it. Consequently the released radix-2 inverse
output is scaled by 2^n = 2¹⁰, and no self-checking testbench catches it (the
shipped testbench has none). We reproduce this bit-exactly at the full-core
RTL level and reported it upstream (issue #7; the empty control FSM is #4).
Our redesign (§4.1) fixes it *for free* as part of the multiplier change.

# 4. Design

## 4.1 K-RED butterfly (invention 1)

**Reduction.** With z = z₁·2^m + z₀ and k·2^m ≡ −1 (mod q),
`k·z₀ − z₁ ≡ k·z` (Lemma 1). Two folds reduce a full product to < 2q:

    d = 3·z[11:0] + 6q − z[27:12]   ≡ 3z,   0 < d < 2¹⁷
    e = 3·d[11:0] +  q − d[16:12]   ≡ 9z,   0 < e < 2q
    r = e ≥ q ? e−q : e             =  9z mod q

`3x = (x<<1)+x`: shifts, adds, one conditional subtraction. Latency 4, ports
identical to `modular_mul.v` — one hardware multiplier (the product) instead
of three.

**Absorbing the factor 9.** The ROM stores W = 9⁻¹·w, so the forward
butterfly's `9·v·W = v·w` is exact; the inverse twiddle `op21(W)=(2·9)⁻¹·w`
is derived from the same word by one `modular_half`, and
`9·(v−u)·op21(W) = ((v−u)·w)/2` — **fusing the missing halving** (Lemma 2).
The add path gets one more `op21`. PWM (both operands data) double-passes the
unit with the stored constant 81⁻¹.

## 4.2 ψ-fold twiddle ROM (invention 2)

For the bit-reversed layout, `w[N/2+j] = ψ·w[j]` (Lemma 3), and ψ=7 gives
`7x = (x<<3)−x`. So we store the 512 lower (9⁻¹-scaled) words and derive the
upper half with a `fold7` gate: shift-sub then three conditional
subtractions, no multiplier, same interface and latency as `tf_ROM.v`. The
relation recurses (`w[N/4+j]=49·w[j]=fold7²`), giving a −75% variant. The
factor-9 scaling and the fold commute (Lemma 4).

# 5. Verification

We verify at three levels, all CI-reproducible.

**Datapath, full domain (SMT).** Exact-width z3 models of each unit, proven
equal to mod-q arithmetic over the whole input domain. Key technique: a
**divider-free congruence encoding** — instead of `r == z mod q` (which
bit-blasts a divider and diverges past ~24 bits), prove the nonnegative
linear identities `3c+6q = d+c₁q`, `3d+q = e+d₁q` and `r < q`. This turned a
2-hour non-converging run into 11 seconds.

**Pipelines, on the RTL (SymbiYosys).** The butterfly and ROM are proven on
the real Verilog with their delay chains, **compositionally**: leaf units are
proven equivalent to behavioural models, then abstracted, so the butterfly
obligation closes in seconds. Assertions are time-local with unconstrained
initial state, so a bounded model check of depth `guard+latency+1` is a
**complete** proof; reset and single-clock/CDC are checked structurally.

**Non-vacuity.** Five RTL mutations (a fold constant, a dropped halving gate,
a skipped twiddle mux, a corrupted ROM word, a wrong fold shift) each make
the corresponding proof fail with a counterexample.

**System level.** The real invented modules, driven through a full N=1024
NTT+INTT under iverilog, give `NTT(x)` = reference and `INTT(NTT(x)) = x`
exactly — the fix and the folded ROM compose correctly. (The reference core,
same harness, reproduces the 2¹⁰-scaled bug.)

# 6. Generalization

All of §4 is parameterized by the Proth prime. A generator computes, per q:
the fold count and offsets, the spurious factor k^F and its inverse, `k·x`
as shift-adds, and the ψ-fold plan; it emits synthesizable RTL and checks
it. We validate **Kyber, q = 3329 = 13·2⁸+1** (ML-KEM) as an independent
instance: the K-RED reducer is checked *exhaustively* over all z < q², and
the generated RTL passes an iverilog sweep. The generator even finds a
tighter Falcon schedule than our hand-written unit — evidence the
construction subsumes the special case.

# 7. Evaluation

**Cost (yosys generic synthesis; PnR is future work — §8).**

| Block | reference | proposed | Δ |
|---|---|---|---|
| modular multiplier | 2176 cells, 3 mults | 1724 cells, 1 mult | −21% cells, −67% DSP |
| butterfly | 2820 cells | 2549 cells (+ inverse-correct) | −10% cells |
| twiddle ROM | 7828 cells, 14322 bits | 1611 cells, 7168 bits | −79% cells, −50% bits |

With d parallel butterflies the DSP saving is ×d; the ROM saving is a direct
BRAM/LUT reduction, ×2 more with the two-level fold.

# 8. Limitations and future work

Cycle-accurate reconstruction of the reference's (unreleased) banked-memory
FSM is incomplete, so whole-core place-and-route numbers — the reviewer-grade
LUT/FF/DSP/BRAM/Fmax on Artix-7, v1 vs v2 — are the main open item; per-module
PnR and the streaming full-transform simulation are done. Generic ψ-fold RTL
emission and per-prime SymbiYosys generation are templated but not yet
automatic. The visual-discovery provenance is reported, not evaluated (no
ablation of the agent loop).

# 9. Conclusion

Starting from a released accelerator and *verifying* it, we found a real
inverse-transform bug, replaced its Barrett multipliers with a verified
Proth-prime K-RED unit that fixes the bug for free, halved its twiddle ROM
with a symmetry specific to bit-reversed negacyclic tables, and showed the
whole construction generalizes with a generator validated on Kyber. Every
number is reproducible from the public repository's CI.

# Reproducibility

All artifacts, proofs and the derivation history are public at
`github.com/NyxFoundation/ntt-fpga-z3`; `proposed/run_all.sh` and the CI
workflow regenerate every claim. [TODO: Zenodo DOI + Dockerfile for artifact
evaluation.]

# References

[TODO: CFNTT TCHES 2022; Longa–Naehrig 2016; K-RED-Shift / Proth-l (eprint
2024/1890); half-memory TFG (Electronics 2024); on-the-fly / FALCON TFG;
masked-NTT verification line (arXiv 2604.*); Falcon/FN-DSA spec; Kyber/ML-KEM
spec. Full citekeys in docs/related-work.md.]
