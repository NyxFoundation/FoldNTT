---
title: "FoldNTT: A Multiplier- and Twiddle-Lean NTT Core with Formally Verified Arithmetic for Proth Primes"
author: Masato Kamba (Nyx Foundation)
date: 2026
nocite: |
  @yosys, @iverilog, @z3
abstract: |
  Hardware for lattice-based post-quantum cryptography spends a large
  share of its area on the number-theoretic transform (NTT), dominated by
  modular multipliers and twiddle storage. FoldNTT is a redesign of the
  released radix-2 CFNTT accelerator (TCHES 2022) for the Falcon / FN-DSA
  prime q = 12289 with one hardware multiplier per butterfly instead of
  three and about half the stored twiddle constants. The Proth shape
  q = 3·2¹² + 1 turns modular reduction into shift-and-add K-RED folds,
  and the bit-reversed twiddle table obeys `w[N/2+j] = ψ·w[j]`, so half
  the table is derived without a multiplier. Checking the released RTL
  against the mathematics also exposed a bug: its inverse transform omits
  a per-stage halving and returns 2¹⁰·x, which the retrofit corrects.
  Every arithmetic block is proven by exact-width SMT and compositional
  SymbiYosys proofs, control-safety invariants by k-induction; the proofs
  are mutation-tested and the composed transform is validated by
  simulation, all rerun by CI. On Artix-7 in a fully open flow, the
  retrofit costs 3→1 DSP48 per butterfly and −50% stored twiddle bits at
  a whole-core Fmax cost of about 4% (best of three seeds; within the
  seed-to-seed spread), measured on the released datapath driven by a
  controller we reconstructed (the reference FSM was never released) and
  validated by full-core simulation; a sequential core with our own
  controller builds to a timing-gated Basys-3 bitstream.
---

# 1. Introduction

Lattice-based post-quantum schemes such as Kyber/ML-KEM [@fips203],
Dilithium/ML-DSA [@fips204], and Falcon/FN-DSA [@falcon] spend a large
share of their cycles in polynomial multiplication, which hardware
accelerates with the number-theoretic transform (NTT), a Fourier-style
transform over integers modulo a prime q. The NTT's hardware cost is
dominated by two resources: the modular multipliers inside the butterflies
and the twiddle ROM. This paper reduces both without
changing the surrounding memory system or control.

We start from a concrete, peer-reviewed artifact: the CFNTT accelerator
[@cfntt], whose contribution is a conflict-free memory mapping
for an in-place radix-2/4 NTT, released as open RTL. From it we build
FoldNTT, an NTT core that preserves the forward transform, corrects the
inverse, and uses a third of the multipliers and about half the stored
constants; every arithmetic block is proven equal to the mathematics and
the composition is validated by simulation. Three components deliver
this.

- **A verified 1-multiplier butterfly (§4.1).** For q = 12289 = 3·2¹²+1 (a
  Proth prime, and Falcon's modulus), the reference's Barrett reduction
  spends two hardware multipliers beyond the unavoidable product. We replace
  them with shift-add **K-RED** folds, leaving one multiplier total, and fold
  the resulting constant factor into the twiddle ROM. K-RED is established in
  software NTTs and in hardware, for Kyber and for FHE-sized moduli (§2);
  our contribution is the verified drop-in retrofit, in which the same ROM
  fold supplies half of the repair for a bug we found in the released
  inverse transform (§3).

- **A ψ-fold twiddle ROM (§4.2).** The bit-reversed
  negacyclic table obeys `w[N/2+j] = ψ·w[j]`; with ψ shift-friendly (Falcon
  ψ = 7), half the ROM is derived by a shift-subtract followed by a
  constant-threshold reduction, with no multiplier. This approximately
  halves the stored words (1023 → 512; the folded table keeps a scaled
  w[0] as a base word); the relation recurses to a quarter algebraically. It is distinct from the negation symmetry used by prior
  half-memory twiddle generators, which is unavailable here because the
  stored ψ-exponents span [0, N) while ψ has order 2N.

- **A functional-verification methodology (§5)** that checks the arithmetic
  and datapath against a mathematical specification, down to the shipped ROM
  contents, reproducibly in CI. This differs from the masking/side-channel
  focus of recent PQC-hardware verification. Its abstractions are
  domain-faithful (the solver, not a hand argument, discharges the
  assume-guarantee seams), its control-safety proofs are inductive, and
  the proofs are mutation-tested (eight mutations over five harnesses). The inverse-transform bug surfaced through
  this checking, not through the shipped testbench.

The K-RED leg generalizes to other Proth NTT primes, with a generator that
emits and checks per-prime reducer RTL (§4.3), validated on Kyber
(q = 3329). §6 reports costs measured in an open FPGA flow (yosys + openXC7
`nextpnr-xilinx`, Artix-7), with no Vivado required: at the whole core,
3→1 DSP per butterfly and half the twiddle storage at a Fmax cost of
about 4% (−21% on Compact-FALCON's ENS normalized-area metric, defined in
§6), and
the inverse-transform bug fixed. Because the released radix-2 core's
control FSM was never published, we reconstructed one from the datapath's
own timing and validated it by full-core simulation (§5); the whole-core
numbers are measured on that controller. The design is one construction
with two instantiations: the streaming retrofit demonstrates the claim on
the published architecture, and a sequential single-butterfly (BFU) core
with our own controller (the "own-FSM core" below) packages the same
verified blocks as a self-contained accelerator that builds to a
bitstream (§6).

# 2. Background

**Negacyclic NTT.** Lattice schemes multiply polynomials in the ring
`R_q = Z_q[x]/(x^N + 1)`. Naively this is an O(N²) convolution; the NTT
turns it into O(N log N) by evaluating at the powers of a primitive N-th root
of unity. The *negacyclic* wrap (the `x^N = −1` quotient) is handled by
pre/post-weighting with powers of ψ, a primitive 2N-th root
(`ψ² = ω`, `ψ^N = −1`), so that a pointwise product in the transform domain
equals the negacyclic convolution back in `R_q`:
$a \cdot b = \mathrm{INTT}(\mathrm{NTT}(a) \odot \mathrm{NTT}(b))$. A radix-2
transform is a sequence of $\log_2 N$ stages of **butterflies**; the forward
pass uses decimation-in-time in natural-to-bit-reversed order (DIT-NR), the
inverse decimation-in-frequency in bit-reversed-to-natural order (DIF-RN),
which lets both share one bit-reversed twiddle table and avoids an explicit
reorder: with g = 2^{9−p} the group size at stage p and 0 ≤ k < g, the
table satisfies w[2g−1−k] = −w[g+k]⁻¹ (mod q), so the inverse factor and
its sign are both absorbed by reading the reversed entry, which is why the
inverse butterfly subtracts in the order (v−u). The DIF-RN inverse butterfly additionally carries a per-stage
$\tfrac12$ scaling (the $N^{-1}$ of the inverse, distributed one factor of
$2^{-1}$ per stage), realized by a "multiply-by-$2^{-1}$" operator `op21`,
the operator the released radix-2 core omits (§3). For Falcon/FN-DSA,
`N = 1024`, `q = 12289`, and the reference uses `ψ = 7` (a primitive 2048-th
root mod q).

**The CFNTT accelerator.** CFNTT [@cfntt] is an in-place, memory-based
radix-2/4 NTT accelerator whose contribution is a **conflict-free memory
mapping**: coefficients are striped across two banks by the parity of
their address (bank = XOR of address bits, offset = address ≫ 1), and the
address generator emits, for every radix-2 stage, the pair of operands a
butterfly consumes. Because the two operands of any stage differ in exactly
the stage's bit, they always fall in different banks. Both are therefore
read (and later written) in the same cycle with no bank conflict, keeping
the single pipelined butterfly fully fed. Twiddles come from one shared ROM of
`N − 1 = 1023` words in the bit-reversed layout `w[i] = ψ^{bitrev(i)}`
(RTL address A holds w[A+1]; w[0] = 1 is not stored), read via a small
twiddle-address generator whose sequence matches the stage/loop
counters. The released radix-2 RTL is what we retrofit; we leave its memory
system, address generators and conflict-free mapping untouched, changing only
the butterfly's arithmetic (§4.1) and the ROM's internals (§4.2).

**Modular reduction.** Barrett and Montgomery are the general-purpose
choices. For Proth primes q = k·2^m+1, K-RED [@longa2016kred] reduces with
shifts and adds. It is established in software NTTs and has hardware
precedent: K²-RED [@bisheh2021k2red] applies it to Kyber's q = 3329, and
shift-add variants (K²-RED-Shift over Proth-ℓ primes) have been evaluated
for the 32- and 64-bit moduli of FHE [@tosun2024modred].

**Twiddle storage.** Prior work reduces the ROM by on-the-fly generation
(a modular multiplier per butterfly) [@krieger2025tool] or by a half-memory
generator using the negation symmetry `W^{N/2} = −1` [@im2024tfg].
We use a different, address-halving relation of the bit-reversed layout
that is multiplier-free when ψ is shift-friendly.

**Verified PQC hardware.** Recent machine-checked work on PQC hardware
targets masking composition and side-channel leakage
[@iskander2026a; @iskander2026b]; for FHE, Casas et al. [@casas2023fhe]
verify a compute engine's NTT datapath and micro-sequencer compositionally
against an ISA specification (§7).

# 3. A bug in the released inverse transform

Because our methodology (§5) checks the RTL against the mathematical
transform rather than against a testbench, it surfaced a functional bug in
the released accelerator. We describe it in full, since it is the
finding that motivates the methodology.

**The defect.** The DIF-RN inverse butterfly must apply a $\tfrac12$ scaling
per stage: the $N^{-1}$ of the inverse transform, distributed as one factor
of $2^{-1}$ each of the $\log_2 N$ stages (paper Alg. 3; the reference's own
Python model applies this as `op21`, $x\cdot 2^{-1}\bmod q = x\,(q{+}1)/2 \bmod q$). The
released radix-2 RTL ships `modular_half.v` but instantiates it nowhere in
`compact_bf.v`: in inverse mode (`sel=1`) the butterfly computes
$(u{+}v,\ (v{-}u)w)$, with w the reversed-table entry of §2, and no
halving. The radix-4 PEs (`PE0–PE3.v`) do
instantiate `modular_half`, so the omission is specific to the radix-2 tree.

**Consequence.** Each inverse stage is a factor of 2 too large, so after
$\log_2 N = 10$ stages the radix-2 inverse output is scaled by
$\mathbf{2^{10}\bmod q}$: $\mathrm{INTT}(\mathrm{NTT}(x)) = 2^{10}x$, not $x$.
The forward transform is unaffected. Because the map is linear, there is no
partial cancellation; the error is exactly a global constant. The output is
therefore a valid-looking vector of residues, indistinguishable from a
correct one without a reference value.

**Bug, or an unnormalized inverse?** An inverse transform that returns
N·x and leaves N⁻¹ to be folded into a later constant is a legitimate
design choice, so the question is whether the omission is intended. Three
facts say it is not. The CFNTT paper's Alg. 3 specifies the per-stage
halving for the radix-2 inverse, and the reference's own Python model
applies it. The released radix-4 processing elements implement it. The
radix-2 tree ships `modular_half.v` but instantiates it in no module, and
no other module of the released radix-2 tree (`top_poly_mul.v` and below)
applies a compensating constant. The radix-2 RTL therefore disagrees with
its own paper and model, and we report it as a bug on that basis.

**Why testing didn't catch it.** The shipped testbench (`tb_top.v`)
drives stimulus and reads memory files but asserts
nothing about the result, and no reference vector is committed. A single
end-to-end functional assertion would have caught the bug.

**How we found and confirmed it.** The round-trip property
`INTT(NTT(x)) = x` failed in our SMT/simulation checks; the counterexample
was a clean global 2¹⁰ factor, which points directly at a missing per-stage
2⁻¹. We confirmed it with bit-exact integer models of the released
datapath modules, each proven equivalent to its Verilog
(`verify_radix2.py`), driven through a complete N=1024 inverse
(`bug_intt_halving.py` reproduces `2¹⁰·x`); localized it to the
un-instantiated `modular_half`; and reported it upstream (issue #7 at
`github.com/xiang-rc/cfntt_ref`; the empty control FSM `fsm.v` is the
related issue #4). We then reproduced it at the full-core RTL level: the
released datapath (banks, address generators, `compact_bf`, `tf_ROM`),
driven by the controller we reconstructed for the missing `fsm.v` (§5),
returns `NTT(x)` exactly and `INTT(NTT(x)) = 2¹⁰·x` on every tested
vector (`run_sim.py`). Both issues are open and unacknowledged at the time
of writing.

**The fix, and what it costs here.** Reinstating the halving costs two
`modular_half` (op21) gates per butterfly, one per output path. In the K-RED
redesign (§4.1) the multiply-path gate acts on the twiddle word rather than
on the product: the ROM stores W = 9⁻¹·w, the inverse twiddle
op21(W) = (2·9)⁻¹·w is derived from that word inside the butterfly's
existing twiddle delay chain, and the multiply then yields ((v−u)·w)/2
directly (Lemma 2). The add path gets the second gate. The fix therefore
adds no multiplier, no latency and no port change; its cost is two
shift-add gates, which a correct reference would also have to pay. Our
verified core round-trips exactly (§5, §6).

# 4. Design

Both techniques are interface-compatible with the reference (same ports,
delay fabric and latencies) and are applied as a pair: the multiplier
returns 9·a·b mod q and the ROM returns 9⁻¹-scaled words, so either one
alone changes the transform. Their contracts (operands < q, mode held
constant during a transform, the corrected inverse) are stated with the
proofs in §5. Figure 1 is the proposed radix-2
butterfly; only the shaded blocks change. We cite four small algebraic
facts as Lemmas 1–4; they are stated in Appendix A, with paper proofs in
the artifact (`docs/lemmas.md`) and machine checks as the certificates.

Table 1 summarizes the design: each algebraic fact and the hardware it
saves.

**Table 1. Algebraic fact → hardware saved.**

| algebraic fact | hardware consequence | measured (§6) |
|---|---|---|
| Lemma 1: K-RED fold for q = 3·2¹²+1 | 3 → 1 DSP48 per butterfly | −67% DSP |
| Lemma 2: halving fuses into the ROM word | inverse-transform bug fixed with two op21 gates, no added multiplier or latency | in `compact_bf_v2` |
| Lemma 3: w[N/2+j] = ψ·w[j] | twiddle ROM stores half the words, no multiplier | −50% stored bits; LUT 241 → 192 |
| Lemma 4: constant scalings commute | K-RED and ψ-fold compose with no correction hardware | end-to-end exact (§5) |

```{=latex}
\begin{figure*}[t]
\centering
\resizebox{0.92\textwidth}{!}{%
\begin{tikzpicture}[
  >={Stealth[length=2.2mm]}, font=\small, line width=0.4pt,
  block/.style={draw, rounded corners=1pt, minimum height=8mm, inner sep=4pt, align=center},
  hi/.style   ={draw, rounded corners=1pt, minimum height=8mm, inner sep=4pt, align=center, fill=black!12},
  reg/.style  ={draw, minimum height=6.5mm, minimum width=8mm, inner sep=2pt},
  dot/.style  ={circle, fill, inner sep=1pt}]
  % ---- inputs (left), stacked u / v / w ----
  \node (u)  at (0,2.4)  {$u$};
  \node (v)  at (0,1.2)  {$v$};
  \node (w)  at (0,0)    {$W$};
  \node[reg, right=5mm of u] (du) {DFF};
  \node[reg, right=5mm of v] (dv) {DFF};
  \node[reg, right=5mm of w] (dw) {DFF};
  \node[reg, right=4mm of dw] (dw2){DFF};
  \node[block, right=6mm of dv] (mux) {mux\\[-1pt]\scriptsize(sel)};
  % ---- changed core: K-RED mult + fused half ----
  \node[hi, right=13mm of mux] (mul) {\texttt{modular\_mul}\\[-1pt]\textbf{K-RED} — \scriptsize 1 DSP (not 3)};
  \node[hi] (half) at ($(mul)+(0,-1.6)$) {\texttt{modular\_half}\\[-1pt]\scriptsize op21($W$) on ROM word};
  % ---- add / sub / op21 ----
  \node[block] (add) at ($(mul)+(5.4,0.7)$)  {\texttt{modular\_add}};
  \node[block] (sub) at ($(mul)+(5.4,-0.95)$) {\texttt{modular\_sub}};
  \node[hi, right=8mm of add] (op) {op21\\[-1pt]\scriptsize INTT $\tfrac12$};
  \node[right=8mm of op]  (bl) {\texttt{bf\_lower}};
  \node[right=13mm of sub] (bu) {\texttt{bf\_upper}};
  % ---- wires ----
  \draw[->] (u)-- (du);  \draw[->] (v)-- (dv);  \draw[->] (w)-- (dw);
  \draw[->] (dw)-- (dw2);
  \draw[->] (dv)-- (mux);
  \draw[->] (mux)-- (mul);
  \draw[->] (dw2) |- (half);
  \draw[->] (half)-- (mul);
  % product of the multiply feeds add and sub from the left
  \coordinate (pt) at ($(mul.east)+(0.5,0)$);
  \draw (mul.east) -- (pt);
  \draw[->] (pt) |- (add.west);
  \draw[->] (pt) |- (sub.west);
  \draw[->] (add)-- (op);
  \draw[->] (op)-- (bl);
  \draw[->] (sub)-- (bu);
  % u bypass: tap after its DFF, run along the TOP (clear of every block) to
  % just left of add, then drop down a rail into add and sub upper-left — u is
  % the pass-through operand of both add (u+vw) and sub (u-vw).
  \node[dot] (ud) at ($(du.east)+(0.5,0)$) {};
  \draw (du.east) -- (ud);
  \coordinate (uc)  at ($(add.west)+(-0.4,0)$);
  \coordinate (uc2) at ($(sub.west)+(-0.4,0)$);
  \draw (ud) -- (uc |- ud) -- (uc);
  \draw[->] (uc) -- (add.170);
  \draw (uc) -- (uc2);
  \draw[->] (uc2) -- (sub.170);
\end{tikzpicture}}
\caption{Proposed \texttt{compact\_bf\_v2}; shaded blocks are the changes vs the
reference. The twiddle port receives the scaled word $W = 9^{-1}w$ and the
single \textbf{K-RED} multiplier computes $9\cdot v\cdot W = v\cdot w$, replacing
the reference's three multipliers. The two \texttt{op21} ($\times\tfrac12$)
gates, one on the ROM word (\texttt{modular\_half}) and one on the INTT add
path, are the \S3 bug fix; forward mode bypasses both. Bypass muxes, delay
chains and the inverse-mode reordering (the subtraction precedes the
multiply and \texttt{bf\_upper} is the multiplier output) are not drawn.
In unscaled twiddles, \texttt{sel}=0 (NTT) yields $(u{+}vw,\;u{-}vw)$ and
\texttt{sel}=1 (INTT) yields $(\tfrac12(u{+}v),\;\tfrac12(v{-}u)\,w)$. Same
ports, delays and latency as the reference \texttt{compact\_bf}.}
\label{fig:datapath}
\end{figure*}
```

The multiplier is the single hardware multiply; the two `op21` (modular_half)
gates, one on the ROM word and one on the add path, are the §3 bug fix.

## 4.1 K-RED butterfly

**Reduction.** With z = z₁·2^m + z₀ and k·2^m ≡ −1 (mod q),
`k·z₀ − z₁ ≡ k·z` (Lemma 1). Two folds reduce a full product to < 2q:

    d = 3·z[11:0] + 6q − z[27:12]   ≡ 3z,   0 < d < 2¹⁷
    e = 3·d[11:0] +  q − d[16:12]   ≡ 9z,   0 < e < 2q
    r = e ≥ q ? e−q : e             =  9z mod q

`3x = (x<<1)+x`: shifts, adds, one conditional subtraction. Latency is 4 and
the ports are identical to `modular_mul.v`, with one hardware multiplier (the
product) instead of three.

A concrete trace, using the artifact's own constants: take v = 5555 and the
stored word W = 9⁻¹·w[1] = 3932 (w[1] = ψ^bitrev(1) = 10810). The product is
z = v·W = 21842260. The first fold takes z₀ = 2388, z₁ = 5332, giving
d = 3·2388 + 6q − 5332 = 75566 < 2¹⁷. The second takes d₀ = 1838, d₁ = 18,
giving e = 3·1838 + q − 18 = 17785 < 2q. One subtraction finishes:
r = e − q = 5496, which is 9z mod q; because the ROM pre-scaled W by
9⁻¹, it equals v·w[1] mod q: the ROM scaling cancels the factor.

**Absorbing the factor 9.** Each fold multiplies the residue by k, so F
folds leave a spurious factor k^F; here k = 3 and F = 2, so the factor is 9.
The ROM stores W = 9⁻¹·w, so the forward
butterfly's `9·v·W = v·w` is exact; the inverse twiddle `op21(W)=(2·9)⁻¹·w`
is derived from the same word by one `modular_half`, and
`9·(v−u)·op21(W) = ((v−u)·w)/2`, which fuses the missing halving (Lemma 2).
The add path gets one more `op21`. Pointwise multiplication (PWM; both
operands are data) double-passes the same unit with the stored constant
81⁻¹ = (k^F)⁻²: two multiplier passes per product, so PWM throughput on one
unit is halved relative to a butterfly multiply (§6 estimates the cost).
The composition is math-checked end-to-end (`kred_math.py`:
INTT(PWM(NTT(a),NTT(b))) equals the negacyclic product), and each pass is
covered by the unit's full-domain proof; our cores do not implement PWM in
RTL, and there is no PWM-specific RTL testbench.

## 4.2 ψ-fold twiddle ROM

For the bit-reversed layout, `w[N/2+j] = ψ·w[j]` (Lemma 3), and ψ = 7 gives
`7x = (x<<3)−x`. We therefore store only the 512 lower (9⁻¹-scaled) words and
derive the upper half with a `fold7` gate, with no multiplier and the same
interface and latency as `tf_ROM.v`:

    t  = (base<<3) − base                       // 7·base ∈ [0, 7q)
    mq = (t ≥ 6q) ? 6q : (t ≥ 5q) ? 5q : … : (t ≥ q) ? q : 0   // 6 parallel cmps
    Q  = upper ? (t − mq)[13:0] : base          // one subtraction, < q

Six parallel constant comparators pick the multiple `mq` and a single
subtraction reduces. We chose this over three chained conditional
subtractions after a logic-depth analysis (§6: LTP 31→26, area down, still
DSP-free). The relation recurses (`w[N/4+j] = ψ²·w[j]` for 0 ≤ j < N/4),
so a quarter table is possible algebraically (checked in
`rom_fold_math.py`); we have not built or measured that variant, whose
derived words need factors up to ψ³ and correspondingly more depth. The
factor-9 scaling and the fold commute (Lemma 4).

§8 describes how the fold was found.

## 4.3 Generalization: other Proth primes

A generator (`kred_gen.py`) computes, per q, the K-RED fold count and
offsets, the spurious factor k^F and its inverse, and `k·x` as shift-adds;
it emits the reducer RTL and checks it. For the ψ-fold it reports the plan
(shift-add form of ψ, stored word counts) but does not yet emit a ROM,
butterfly, controller or proof harness (§8). One caveat on scope: the K-RED leg applies to any Proth NTT
prime, but the ψ-fold's multiplier-free form additionally needs a
shift-friendly ψ (as in Falcon's ψ = 7); for a general q the fold becomes
a small constant multiply, which may not beat storing the words. We
validate Kyber, q = 3329 = 13·2⁸+1 (ML-KEM), as an independent
instance: the K-RED reducer is checked exhaustively over all z < q²,
and the generated RTL passes a 60k-vector iverilog sweep (the RTL check is
a simulation sweep, not exhaustive). Kyber validates the reducer only:
ML-KEM's NTT is incomplete (q − 1 = 13·2⁸ is not divisible by 2N = 512, so
no primitive 2N-th root exists), Lemma 3's full negacyclic table does not
describe its twiddle set, and folding an incomplete-NTT table is separate
work. The generator finds a tighter Falcon schedule than our hand-written
unit, evidence that the construction subsumes the special case.

When is the fold cheap? Two parameters decide. The fold count F stays at
2–3 whenever m is large relative to k's width, and each fold's k·x costs
adders proportional to the signed-digit weight of k. Running the artifact's
own planner (`generator/kred_gen.py`) on primes used in deployed schemes
gives Table 2:

**Table 2. K-RED fold economics for deployed NTT primes.**

| prime | q | folds F | k·x cost (signed-digit form) |
|---|---|---|---|
| Falcon | 3·2¹² + 1 | 2 | 1 add |
| Kyber / ML-KEM | 13·2⁸ + 1 | 2 | 2 adds |
| Dilithium / ML-DSA | 1023·2¹³ + 1 | 2 | 1 subtraction (k = 2¹⁰−1) |
| BabyBear | 15·2²⁷ + 1 | 2 | 1 subtraction (k = $2^4{-}1$) |
| Goldilocks | (2³²−1)·2³² + 1 | 3 | 1 subtraction (k = 2³²−1) |

For Goldilocks, k^F ≡ 1 (mod q), so no ROM scaling is needed at all. The
constant multiply k·x is therefore potentially inexpensive for NTT primes
whose k has low signed-digit weight, which covers the deployed lattice
schemes and lets an FHE or ZK deployment choose residue-number-system
(RNS) primes accordingly, but not for arbitrary RNS primes with random
large k; total cost also depends on width, fold count and pipeline
placement, which Table 2 does not capture. Table 2 is the planner's own output
(`kred_gen.py` prints it, with a sampled validation of each schedule). The
cost column is analytical: the emitted RTL currently uses the addition-only
set-bit form of k·x, and the signed-digit figure is the cost of the
equivalent subtractive form, not a synthesized datapath. We evaluated 14-bit and
12-bit q in RTL; the divider-free congruence encoding is linear in the fold
identities and is expected to scale to RNS-sized moduli (30–64 bit), but we
have not run those proofs; a BabyBear (q = 15·2²⁷+1) z3 instance is the
natural next data point.

# 5. Verification

**Correctness guarantee.** The guarantee has three tiers.

- *Proven for all inputs in scope:* each arithmetic unit over its full
  domain; the butterfly with its real delay chains, in each mode; the ROM
  at every legal address, as a 9⁻¹-scaled refinement of the shipped table;
  control-safety invariants of the own-FSM core under arbitrary host
  behaviour. Domain-faithful abstractions discharge the seams between
  these proofs.
- *Validated by simulation* against independent goldens: the composed
  streaming datapath (two seeded vectors), the own-FSM core (four
  round-trip and two inverse-only vectors, freshness-enforced) and the
  generated Kyber reducer (60k vectors). A monolithic proof of the
  ~150k-cycle round trip is beyond bounded model checking (§8).
- *Outside both:* vendor-tool timing, physical hardware, and side
  channels.

We verify at three levels, all CI-reproducible, with z3 [@z3],
SymbiYosys [@yosys] and Icarus Verilog [@iverilog].

**Datapath, full domain (SMT).** Exact-width z3 models of each unit are
proven equal to mod-q arithmetic over the whole input domain. The key
technique is a **divider-free congruence encoding**: instead of asserting
`r == z mod q`, which bit-blasts a divider and diverges past ~24 bits, we
prove the nonnegative linear identities `3z+6q = d+z₁q`, `3d+q = e+d₁q`
and `r < q` (z = z₁·2¹² + z₀ as in §4.1, d = d₁·2¹² + d₀; the first
follows from d = 3z₀ + 6q − z₁ and 3·2¹²·z₁ = (q−1)·z₁). The same obligation that had not converged after two hours with the
divider closes in 11 seconds.

**Pipelines, on the RTL (SymbiYosys).** The butterfly and ROM are proven on
the real Verilog with their delay chains, under the assumptions that
operands are < q and the mode input is held constant for the proof
(one harness per mode), compositionally: leaf units are
proven equivalent to behavioural models, then abstracted, so the butterfly
obligation closes in seconds. The abstractions are **domain-faithful**: each
behavioural model returns an unconstrained value whenever an operand lies
outside the range its leaf proof justifies (`< q`), so the composite proof
can only pass if no leaf in the asserted cone ever sees an unreduced
operand. The assume-guarantee domain seam is thus discharged by the solver,
leaving no manual "operands stay reduced" argument in the trust base; a
future edit that violates it becomes a counterexample rather than a silently
unsound abstraction. Assertions are time-local: each compares an output with the inputs
`latency` cycles earlier, gated by a saturating `guard` counter that
suppresses the first `guard` cycles after the unconstrained initial state.
A bounded model check of depth `guard+latency+1` therefore explores every
assertion window and is a complete proof; reset and single-clock/CDC are
checked structurally.

**Control, by induction (SymbiYosys).** The own-FSM core's control plane is
proven by **k-induction** with the datapath stubbed to unconstrained
sources. The invariants are the twiddle-counter closed forms
`rr = 2^(9−p) + k` (forward) and `rr = 2^(10−p) − 1 − k` (inverse), from
which the two external preconditions follow: every issued twiddle-ROM
address lies in the ROM's proven domain, and the two RAM write ports
never target the same address. The `busy`/`done` protocol is proven
alongside, under arbitrary host/start behaviour in both modes.
Data-independence of the control flow is structural rather than a theorem
of this proof: the FSM's next-state logic reads only its own counters and a
wait counter, and the datapath is stubbed to unconstrained sources, so no
data signal lies in the control's input cone. The transform's cycle count
is fixed by that structure and is measured and asserted by the artifact's
`run_check.py`, which asserts every reported count within a 70k–80k budget.
This is not a constant-time certification: the datapath is unanalyzed for
power or electromagnetic leakage (§8); the claim is only that latency and
control flow do not depend on the data. Host words are reduced mod q on
load (one conditional subtract suffices: a 14-bit word is < 2q), and the
proof asserts that every host write into the RAM is < q. Engine writebacks
are outside this proof (the datapath is stubbed); their reducedness
follows from the butterfly proof, whose outputs are < q for inputs < q,
provided the host loads all N coefficients before starting. The proof
establishes safety invariants, not liveness: it does not show that a
transform completes or that every butterfly is issued exactly once, which
the simulations cover.

**Non-vacuity.** Non-vacuity is mutation-tested: eight RTL mutations
across the five harnesses (`fv_kred`, `fv_bf_v2_ntt`, `fv_bf_v2_intt`,
`fv_rom_fold`, `fv_core`): a fold constant, a dropped halving gate, a
skipped twiddle mux, a corrupted ROM word, a wrong fold shift, a swapped
subtraction operand, the abstraction's domain predicate forced false (so
the behavioural model returns unconstrained values for every input), and a
mis-seeded FSM counter. Each must produce a counterexample; a harness
crash does not count as a kill. This is selected fault-detection evidence,
not a proof that no obligation is vacuous.

**System level.** The proposed modules, driven through a full N=1024
NTT+INTT under iverilog (`run_stream.py`, which first reads all 1023 words
out of the folded ROM and then streams them to the butterflies, so it
checks value composition rather than the ROM's live delivery timing,
which the sequential core exercises), give `NTT(x)` = reference and
`INTT(NTT(x)) = x` exactly, showing that the fix and the folded ROM values
compose correctly. The complete own-FSM core is checked more strongly
(`run_check.py`): multi-vector round-trips (including raw 14-bit inputs
≥ q, exercising the load reduction), the post-NTT memory compared against
an independently coded Python golden that shares only the shipped
`tf_ROM.v` table (so a bug in the RTL arithmetic is detected on the tested
vectors), and the inverse validated by bijectivity
(`NTT_golden(INTT_rtl(y)) = y`). That harness enforces dump freshness:
every simulation artifact is deleted before the run and required after it,
and simulator exit codes are checked. We adopted this discipline after a
repository reorganization silently disconnected an earlier cross-check.

**Whole banked core.** The released radix-2 core cannot run as shipped:
its `fsm.v` is empty. We reconstructed a controller (`fsm_recon.v`) from
the datapath's own timing (registered bank and twiddle addresses at
issue+1, bank and ROM reads at issue+2, butterfly latency 6, write
address and write-side select at issue+8) and drive the complete
`top_poly_mul`, banks and networks included, through NTT then INTT
(`run_sim.py`, five vectors: three seeded random, all q−1, an impulse,
fresh dumps). With the shipped `compact_bf` and `tf_ROM` the core returns
`NTT(x)` exactly and `INTT(NTT(x)) = 2¹⁰·x` (the §3 bug at full-core
level); with `compact_bf_v2` and `tf_rom_fold` it round-trips exactly.
Both take 5290 cycles per 1024-point transform from launch to `done`
(10 stages × (512 issues at one butterfly per cycle + 17 cycles of drain
and turnaround)), identical for every vector and both variants, which
the harness asserts; the host must hold the mode input until `done`,
because the shipped twiddle-address generator decodes it live. This controller is consistent with the released datapath
but is a reconstruction, not the authors' original; its schedule, not
theirs, is what the whole-core numbers in §6 measure.

Figure 2 draws the resulting boundary; Appendix B tabulates every
obligation with its method and scope. All of it is re-run by CI on every
push.

```{=latex}
\begin{figure}[!t]
\centering
\begin{tikzpicture}[font=\scriptsize,
  zone/.style={draw, rounded corners=1.5pt, align=left, inner sep=5pt,
               text width=0.88\columnwidth}]
\node[zone, fill=black!14] (p) {\textbf{Proven for all inputs in scope}
  (z3 + SymbiYosys)\\[1pt]
  K-RED unit, full 28-bit domain \; $\cdot$ \; fold7 \; $\cdot$ \;
  $9\cdot$ROM $\equiv$ shipped table, every legal address \; $\cdot$ \;
  butterfly, latency-exact, each mode \; $\cdot$ \;
  FSM control-safety invariants (k-induction, any host behaviour) \; $\cdot$ \;
  host writes $< q$};
\node[zone, fill=black!5, below=2mm of p] (s)
  {\textbf{Validated by simulation and mutation testing} (independent
  goldens)\\[1pt]
  composed $N{=}1024$ streaming datapath \; $\cdot$ \; own-core NTT/INTT
  round-trips \; $\cdot$ \; generated Kyber reducer \; $\cdot$ \;
  8-mutation sweep};
\node[zone, below=2mm of s] (o) {\textbf{Outside scope:}
  vendor timing \; $\cdot$ \; physical boards \; $\cdot$ \;
  power/EM side channels};
\end{tikzpicture}
\caption{The verification boundary. Everything in the top zone is proven
for every input in its stated scope; the middle zone is exercised by
simulation against independent goldens and by the mutation sweep; the
bottom zone is explicitly out of scope (\S8).}
\label{fig:boundary}
\end{figure}
```

The harnesses themselves are reusable: each is a self-contained SymbiYosys
or Python file parameterized per module, and the three disciplines they
encode (counterexample-only mutation kills, domain-faithful abstraction,
and BMC-complete time-local assertions) are not specific to this core.
Adapting them to another core means re-deriving the leaf domains and
control invariants; per-prime harness generation is templated but not yet
automatic (§8).

# 6. Evaluation

We report FPGA-primitive (`yosys synth_xilinx`, 7-series) and post-route
(openXC7 `nextpnr-xilinx`, xc7a100t) numbers; the claims rest on these.
Technology-independent generic-gate counts are in the artifact
(`docs/evaluation.md`) and are quoted below only where they differ
materially from the FPGA mapping. Vendor (Vivado) confirmation and
physical on-board execution remain outside CI (§8).

Table 3 gives the measured resources, per module and for the whole core.

**Table 3. FPGA resources, per module and whole core (Artix-7, `synth_xilinx`; LTP = longest topological path, yosys `ltp`, a logic-depth proxy).**

| | LUT | FF | **DSP48** | RAMB18 | LTP |
|---|---|---|---|---|---|
| `modular_mul` (Barrett) → `modular_mul_kred` | 29 → 83 | 101 → **74** | **3 → 1** | — | 17 → 21 |
| `compact_bf` (ref) → `compact_bf_v2` | 158 → 231 | 297 → 270 | **3 → 1** | — | — |
| `tf_ROM` → `tf_rom_fold` | 241 → **192** | 14 → 15 | 0 → 0 | — | 7 → 26 |
| whole core: reference `top_poly_mul` | 784 | 580 | **3** | 2 | — |
| whole core: proposed `top_poly_mul_v2` | 819 | 500 | **1** | 2 | — |

Figure 3 is the summary: what the retrofit changes, normalized to the
reference core. These numbers support the following observations.

```{=latex}
\begin{figure}[!t]
\centering
\resizebox{\columnwidth}{!}{%
\begin{tikzpicture}[font=\scriptsize]
\newcommand{\perfbar}[4]{%
  \draw[fill=black!8, draw=black!30] (0,#1) rectangle (5.2,#1+0.34);
  \draw[fill=black!45, draw=black!55] (0,#1) rectangle (#2,#1+0.34);
  \node[anchor=east] at (-0.12,#1+0.17) {#3};
  \node[anchor=west] at (5.32,#1+0.17) {#4};}
\perfbar{2.55}{1.73}{DSP48 per butterfly}{33\% (3 $\to$ 1)}
\perfbar{1.85}{2.60}{stored twiddle bits}{50\%}
\perfbar{1.15}{4.12}{ENS area score}{79\% (969 $\to$ 767)}
\perfbar{0.45}{5.00}{whole-core Fmax}{96\% (143 $\to$ 138 MHz, best of 3 seeds)}
\draw[black!50, dashed] (5.2,0.3) -- (5.2,3.05)
  node[above, black, font=\scriptsize] {reference = 100\%};
\end{tikzpicture}}
\caption{The streaming retrofit vs the reference core, normalized to the
reference (100\%, dashed). Lower is better for the first three bars; Fmax
is post-route on the whole core with the reconstructed controller (\S6).
Forward transform unchanged, inverse transform corrected (\S3).}
\label{fig:summary}
\end{figure}
```


- The headline result is the DSP count: 3 → 1 per butterfly (−67%) on
  real primitives, with −27% FF on the multiplier. Each additional
  parallel butterfly costs another set of multipliers, so the saving is
  two DSP48 per instantiated butterfly; whether DSPs, bank ports, twiddle
  delivery or LUTs bound the achievable parallelism depends on the
  surrounding memory system, which we do not scale here. The butterfly
  additionally becomes inverse-correct (§3).
- K-RED trades DSP for LUT/carry logic (multiplier LUTs 29 → 83; whole
  core +5% LUT). This is favourable when DSPs bound the design and a small
  LUT cost when they do not.
- On FPGA, the twiddle ROM's win is the −50% in stored bits rather than a
  large logic cut. Under generic-gate synthesis the folded ROM is −79%
  cells (7828 → 1611), but that figure does not transfer: at N=1024 the
  table maps to distributed LUT-ROM, where the fold saves ≈20% LUT
  (241 → 192; fold7 adds logic). The stored-bit halving converts to a BRAM
  saving only when the halved table crosses a block-RAM allocation
  boundary; at N=1024 both 1023 and 512 words of 14 bits fit one RAMB18.

**Timing (logic-depth proxy, `ltp`).** K-RED adds ~4 logic levels vs Barrett
(21 vs 17, both latency-4 pipelined; Barrett's DSP hides its own multiply
delay). The ψ-fold's real cost is depth on the derived-half ROM read
(LTP 26 vs 7 for a plain lookup): a logic-depth analysis drove a redesign of
`fold7` from three chained conditional subtractions to six parallel
comparators + one subtraction (LTP 31 → 26, LUT 214 → 192, still DSP-free,
re-verified). The measured Fmax cost is small (see the post-route Fmax paragraph
below); a pipelined fold7 would remove the ROM-read depth at
+1 latency.

**Whole-core area.** The last two rows of Table 3 synthesize the entire
core (one butterfly + two conflict-free banks + twiddle ROM + address
generators + FSM), reference vs proposed.

At the core level the DSP count falls 3→1 (scaling ×d with parallel
butterflies), FF falls 14%, and LUT rises 4% (the K-RED DSP→LUT trade
slightly exceeds the ROM's LUT saving). RAMB18 is unchanged: the two BRAMs
are the data banks, and both twiddle ROMs map to distributed LUT-ROM, so the
ψ-fold's −50% stored bits does not cut BRAM count at N=1024. Both cores
carry the reconstructed controller that `run_sim.py` validates end-to-end
(§5), so these are figures for a working streaming core, with the caveat
that the controller's schedule is ours, not the CFNTT authors'.

**A complete own-FSM core, through to a bitstream.** The released radix-2
core's control FSM is an empty file (upstream issue #4; the radix-4 tree
does ship one), which caps any radix-2 retrofit at the streaming/module
level. We therefore also package the verified blocks into a minimal
complete accelerator with our own sequential single-BFU FSM (§5's induction proof): one `compact_bf_v2`, the ψ-fold ROM, one dual-port BRAM, and ≈74k
cycles per 1024-point transform (~1.5 ms at 50 MHz). This is a high-latency
design point (one butterfly at a time, no overlap between butterflies);
the conflict-free streaming schedule above is the throughput design point. On `synth_xilinx` it maps to 1 DSP48 +
1 RAMB18 + ~600 LUT / ~186 FF, a small fraction of the Basys-3 part
(xc7a35t). The fully open flow (yosys → openXC7 `nextpnr-xilinx` → prjxray
`fasm2frames` → `xc7frames2bit`) produces a self-test bitstream whose
build is timing-gated: every clock nextpnr reports must close ≥ 50 MHz
(the 100 MHz board clock is constrained; the 50 MHz core clock is a
fabric-divided clock that nextpnr reports separately), and the core clock
closes at 70–95 MHz across seeds. The self-test loads `x[i] = 7i+1 mod q`,
runs NTT then INTT, and reports `INTT(NTT(x)) = x` on the LEDs. The
wrapper passes in RTL simulation; we have not run the bitstream on a board
(§8).

**Post-route Fmax (open flow, no Vivado).** At the whole core the retrofit
reaches 137.5 MHz against the reference's 143.1 MHz, best of three seeds
(−4%; `top_poly_mul` vs `top_poly_mul_v2`, the same RTL configurations as
the area numbers: area from a hierarchical `synth_xilinx`, timing from a
flattened one, both with `keep` attributes on the data banks, multipliers
and ROMs, which are otherwise unobservable at the top-level ports and
would be removed). The three seeds span 127–143 MHz for the reference and
130–138 MHz for the retrofit (medians 136 and 134 MHz), so the difference
is inside the seed-to-seed spread; each seed's nextpnr log is archived,
but three seeds do not resolve the difference and the flow does not
extract critical-path endpoints, so we read this as "a few percent", not
as a precise figure. That the gap is far
smaller than at the butterfly is consistent with the conflict-free memory
system, address generators and FSM, identical in both, setting the
critical path. Both netlists carry the same reconstructed controller (§5),
so the comparison is like-for-like, but the absolute figure is not CFNTT's
published one. The module-level numbers behind this, using openXC7's
`nextpnr-xilinx` + artix7 chipdb on xc7a100t, register-wrapped modules,
best of 3 seeds: `modular_mul` (Barrett) reaches 243 MHz vs
`modular_mul_kred` 232 MHz (−4%), so 3→1 DSP costs little clock speed at
the multiplier; `compact_bf` (reference) reaches 169 MHz vs
`compact_bf_v2` 123 MHz (−27%), the module-level gap that shrinks to a few
percent at the core. Two effects plausibly contribute to that gap: the reference
omits the §3 halving, so a corrected reference would also pay for those
gates, and the K-RED+op21 logic lengthens the critical path vs a single
DSP multiply. We have not measured a corrected-Barrett baseline or
isolated the two effects, so this attribution is conjecture. At the module
level the design trades butterfly Fmax for DSPs and twiddle memory; adding
a pipeline stage to the K-RED path or to fold7 is an untested option that
would cost one cycle of latency and a controller change. As with area, the
relative comparisons are what the claims rest on; the absolute megahertz
figures are open-flow estimates from nextpnr-xilinx's timing
model, pending vendor static timing analysis (§8).

**Positioning vs Falcon-NTT accelerators.** CFNTT and Compact-FALCON, the
two closest designs, both target q = 12289 and both use Barrett with full
twiddle ROMs; neither of our contributions appears in them. The two "this
work" rows are the two instantiations of the one construction: the
streaming retrofit carries the like-for-like comparison, the own-FSM core
is the design point that executes end-to-end. Table 4 shows the
comparison.

**Table 4. Comparison with Falcon-NTT accelerators (Artix-7).**

| design | DSP | Fmax | NTT-1024 cycles / time | ENS† | formal proof | executes end-to-end |
|---|---|---|---|---|---|---|
| CFNTT [@cfntt] (base, our flow*) | 3 | 143 MHz | 5290‡ / 37.0 µs | 969 | not reported (released inverse has the §3 defect) | RTL sim, reconstructed FSM |
| **this work** (streaming retrofit) | **1** | 138 MHz | 5290‡ / 38.5 µs | **767** | blocks (§5) | RTL sim, reconstructed FSM |
| **this work** (own-FSM core, xc7a35t) | **1** | 70–95 MHz | ~74k / ~1.5 ms @ 50 MHz | — | blocks + control safety (§5) | bitstream + RTL self-test (no board run) |
| Compact-FALCON [@dam2025compactfalcon] | 20 | 134 MHz | 640 / 4.78 µs | ≈8143 | no | as reported |

*Base area and Fmax are measured on the released radix-2 datapath driven
by our reconstructed controller (§5), identical in the two streaming rows;
they are not CFNTT's published figures, which come from a vendor flow on
the authors' own configuration and their own (unreleased) controller.

†ENS = LUT/4 + FF/8 + BRAM×200 + DSP×100 (Compact-FALCON's own normalized
area metric), computed from the area tables above. All on Artix-7; ours/base
measured in the open flow (§6), Compact-FALCON as reported from Vivado.
Different toolchains count LUTs differently, so the comparison that
carries weight is base→ours in one flow (−21%).
Compact-FALCON is a combined FFT+NTT accelerator (17395 LUT / 7950 FF /
20 DSP / 4 BRAM), hence its far larger ENS.

‡Measured in RTL simulation with the reconstructed controller (§5):
10 stages × 512 butterflies at one butterfly per cycle plus per-stage
drain and start/stop overhead, excluding host transfer; identical in base
and retrofit and for every vector (asserted). The time column divides by
the unrounded post-route Fmax (143.14 and 137.51 MHz). The own-FSM row's count is measured by
`run_check.py`.

We compare against each design in turn. Against the base (same
architecture, same flow) the comparison is like-for-like: ENS −21%
(969→767), driven by 3→1 DSP, with the forward transform unchanged, the
inverse corrected (§3), and Fmax within a few percent. One cost the transform-level rows do not show is pointwise
multiplication, which our cores do not implement in RTL: on one K-RED
unit it would pass the multiplier twice (§4.1), so a full negacyclic
product (two forward transforms, PWM, one inverse) at N = 1024 takes an
estimated 3·5290 + 2048 versus 3·5290 + 1024 cycles, about +6%.
Against Compact-FALCON we do not claim a throughput win: it is roughly 8×
faster per NTT (4.78 vs 38.5 µs), but it is a
different design point, a throughput-optimized combined FFT+NTT accelerator
that is ~10× our ENS and spends 20 DSPs. Ours is a minimal single-BFU
NTT core; its advantages are DSP and area cost and the verification
evidence, not latency. The construction supports a parallel-BFU instantiation
(independent butterflies behind the conflict-free banks, saving two DSPs
per lane), which would trade the area lead for throughput and needs a
multi-lane conflict-free schedule and enough bank ports; we do not build or
measure it. The own-FSM core serves the opposite
design point: area-constrained deployments where a verified,
self-contained core matters more than latency.

**Energy.** The open flow provides no power model, so we make no
quantitative energy claim. Qualitatively, DSP dynamic power is a major
term in multiplier-bound NTT cores, so 3→1 DSP at equal Fmax and equal
cycle count plausibly lowers energy per transform, partially offset by the
added LUT/carry logic; vendor power estimation or board measurement is
future work (§8).

# 7. Related work

**NTT accelerators and conflict-free memory.** In-place NTT hardware must
resolve the read/write bank conflicts of the butterfly access pattern; CFNTT
[@cfntt] contributes a parity-based conflict-free mapping for radix-2/4,
which we retrofit. Other Falcon/Kyber accelerators
[@dam2025compactfalcon; @krieger2025tool] target throughput or
flexibility; the two closest Falcon-NTT designs, CFNTT and Compact-FALCON,
both use Barrett reduction with full twiddle ROMs (§6), so neither the
K-RED retrofit nor the ψ-fold appears in them.

**Modular reduction.** Montgomery and Barrett are the general-purpose
choices. K-RED [@longa2016kred] exploits Proth primes `q = k·2^m+1` for a
shift-add reduction and is established in software NTTs. In hardware,
K²-RED [@bisheh2021k2red] applies it to Kyber's q = 3329, and shift-add
variants (K²-RED-Shift over Proth-ℓ primes) have been evaluated for the
32- and 64-bit moduli of FHE [@tosun2024modred]. Our contribution is a verified, drop-in retrofit of the
reduction into a published accelerator, with the residual factor folded
into the twiddle ROM and the same fold reused to correct the inverse
transform.

**Twiddle storage.** Prior art shrinks the twiddle ROM by on-the-fly
generation (a modular multiplier per butterfly) [@krieger2025tool] or by a
half-memory generator using the negation symmetry `W^{N/2} = −1`
[@im2024tfg]. The negation symmetry is unavailable here because the table
stores ψ-powers with exponents in `[0, N)` while ψ has order 2N: no two
stored exponents differ by N. The ψ-fold instead uses the address-halving
relation `w[N/2+j] = ψ·w[j]`, which holds for a bit-reversed power table
(in natural order the corresponding factor is ψ^{N/2}, not
shift-friendly); for a shift-friendly ψ it is multiplier-free, it recurses
to a quarter algebraically, and the half-table RTL is proven to match the
shipped ROM (up to the 9⁻¹ scaling) at every legal address.

**Verified PQC hardware.** Recent machine-checked verification of PQC
hardware targets masking and side-channel composition
[@iskander2026a; @iskander2026b]: leakage properties rather than
functional correctness of the arithmetic against a mathematical
specification. Closest to our methodology, Casas et al. [@casas2023fhe]
formally verify the NTT datapath and micro-sequencer of an FHE compute
engine compositionally against an ISA specification and report RTL bugs
found in the process; their target is a proprietary 32-bit RNS engine.
We apply a similar block-plus-control decomposition to an open, published
PQC accelerator, retrofit it, and make the contracts and every check
reproducible in CI; that functional check of a released artifact down to
its ROM contents is what surfaced the §3 bug. Our SMT/BMC/mutation toolkit
uses standard techniques; the contribution is their composition into a
reproducible, whole-artifact functional verification (proofs for the
blocks and control invariants, simulation for the composition) and its use
as a design driver.

# 8. Discussion

**How the techniques were found.** Both came out of an iterative
design loop, run as an experiment in LLM-assisted hardware design on top
of visually-3d, a tool we built that renders an architecture as a 3D
floor-plan model grounded in its RTL. One iteration of the loop: (1) formally verify the current design;
(2) regenerate the 3D model from the verified source; (3) show rendered
screenshots to a vision-language model, which critiques the scene and
looks for structure; (4) turn any observation into a concrete design
change; (5) verify the change before accepting it. Figure 4 shows the
model at five points along the loop's 37 revisions. The K-RED retrofit
entered at step (4) as a conventional optimization; the ψ-fold was
noticed at step (3): once K-RED had shrunk the arithmetic, the twiddle
ROM was visibly the largest remaining block, and the question of why
half the table should not be derivable had a mathematical answer
(Lemma 3). Every candidate had to pass step (5), so a visually suggested idea could
be adopted without weakening the correctness argument.

```{=latex}
\begin{figure*}[t]
\centering
\includegraphics[width=\textwidth]{../assets/discovery-timeline.png}
\caption{The design loop's 3D model across its revisions: first draft
(v1); the matured CFNTT floor plan, Barrett reduction with 3 DSP per
butterfly (v31); the K-RED butterfly landing (v32); the revision in which
the ψ-fold was spotted (v36); the final FoldNTT model (v37). Each panel
is rendered by visually-3d from the RTL-grounded scene at that step.}
\label{fig:discovery}
\end{figure*}
```

The full model history (every revision, its renders, and the
verification verdicts between them) is published in the visually-3d
gallery at `visually-3d.kingmasatojames.workers.dev/#/s/ntt-fpga`, and the
rendered montage is in the repository (Figure 4), so the process is
inspectable end to end. We claim no generality for it: this is one design, found once, with no ablation of the loop's
components; the mathematics and the proofs stand on their own.

**Limitations and future work.** Whole-core area (LUT/FF/DSP/BRAM) and per-module post-route Fmax are
both now measured via the open flow (§6, openXC7 nextpnr-xilinx on
xc7a100t). Whole-core Fmax is also measured (143 vs 138 MHz, best of
three seeds) on the core with the reconstructed controller. The
functional whole-core gap is closed by the own-FSM core (§6): it
round-trips exactly, its control-safety invariants are proven, and it builds to a bitstream. What
remains: (a) the streaming core runs on a controller we reconstructed
from the released datapath's timing and validated by simulation (§5); it
is one controller consistent with that datapath, and the original timed
behaviour of the unreleased FSM, including its cycle count, stays
unknowable, so the whole-core figures are ours rather than CFNTT's; (b) the own-FSM core is sequential, and a
pipelined 2-bank instantiation for ~1 butterfly/cycle is future work;
(c) full-transform functional correctness is simulation-validated, and the
formal proofs cover the listed blocks and the control-safety invariants,
since a ~150k-cycle end-to-end BMC is out of reach; (d) physical on-board execution and vendor (Vivado) confirmation of
the open-flow figures have not been performed; (e) power/EM side channels
are out of scope (control-flow latency is data-independent by structure,
§5, but nothing is claimed about leakage); (f) pointwise multiplication is
not implemented in RTL, and on one K-RED unit it would cost an estimated
≈6% on a full polynomial multiplication (§6), which a second reducer or a
Barrett PWM unit would remove; and (g) the per-module Fmax flow keeps
only the best of three seeds, so timing differences of a few percent are
not resolved. Generic ψ-fold RTL emission and per-prime SymbiYosys
generation are templated but not yet automatic.

# 9. Conclusion

FoldNTT preserves the forward transform of the accelerator it started
from, corrects its inverse to the specification, and uses a third of the
multipliers and about half of the stored constants; every
arithmetic block is proven equal to the mathematics and the composition is
validated by simulation. Verifying the
released accelerator exposed an inverse-transform bug; the K-RED
retrofit fixes it with two shift-add gates and no added multiplier or
latency, the ψ-fold halves the twiddle ROM, and a
generator extends the construction to other Proth primes. Two
instantiations demonstrate the construction: the drop-in streaming
retrofit, and a complete own-FSM core, with control-safety invariants
proven by induction, built to a timing-gated Basys-3 bitstream in a fully
open flow, whose self-test passes in RTL simulation. The proofs,
simulations and area numbers are re-run by the public repository's CI;
the Fmax and bitstream flows are one-command scripts outside hosted CI.

# Reproducibility

Everything in this paper is public at `github.com/NyxFoundation/FoldNTT`
(the retrofitted RTL, the reference CFNTT as a submodule, all proofs, the
generator, the FPGA flow, and the rendered design-loop montage; the
design-loop revision history is at
`visually-3d.kingmasatojames.workers.dev/#/s/ntt-fpga`); the proof,
simulation and area classes are re-run by CI. All RTL, proofs, generator and flow scripts are
MIT-licensed; the upstream `cfntt_ref` submodule is itself MIT
(© xiang-rc). A repo `flake.nix` pins the toolchain (yosys, SymbiYosys,
yices, iverilog, uv for the z3 scripts, and the exact openXC7 tag), so
`nix develop` drops into a shell where every script below runs with no
further setup; hosted CI instead uses the OSS CAD Suite for the formal
flow, so the two environments differ in tool versions. Each class of
claim has a one-command reproduction; all paths below are relative to the
repository root. The GitHub Actions workflow reruns the proof,
simulation and area classes on every push. The Fmax flow runs under the
flake; the bitstream script additionally resolves yosys and the prjxray
converters through the nix registry rather than the flake lock. Both stay
outside hosted CI (the place-and-route chip database is too large for
hosted runners), as do the board-wrapper simulation and the own-core
synthesis (`ntt-core/README.md`):

- **Functional verification** (`run_all.sh`): the exact-width z3
  proofs (K-RED unit, fold7), the SymbiYosys proofs (butterfly miter with
  domain-faithful abstractions, scaled ROM equivalence, own-FSM control
  safety by k-induction, reset/CDC, the 8-mutation sweep), the iverilog
  streaming round-trip (`verification/fullcore/run_stream.py`), the
  own-core checks (`ntt-core/run_check.py`) and the generator
  (`generator/kred_gen.py`, `generator/gen_check.py`); the
  reference-datapath equivalence suite and the §3 bug reproduction are
  `verification/reference-fv/run_all.sh` and
  `verification/bug_intt_halving.py`.
- **Own-FSM core** (§5, §6): `ntt-core/run_check.py` runs the
  freshness-enforced multi-vector round-trip, independent-golden NTT/INTT
  checks, and the streaming cross-validation; `ntt-core/fv_core.sby` runs
  the control-safety induction proof.
- **Area** (§6): `fpga/fpga_cost.sh` (per module) and
  `fpga/fpga_cost_core.sh` (whole core), via `yosys synth_xilinx`.
- **Post-route Fmax** (§6): `fpga/fmax.sh` and `fpga/fmax_core.sh`, via
  openXC7 `nextpnr-xilinx` on Artix-7 `xc7a100t`; no Vivado, no vendor
  download. The `flake.nix` pins the working openXC7 tag
  (`github:openXC7/toolchain-nix/0.8.2`) and exports `NP`/`CHIPDB`, so under
  `nix develop` both scripts run argument-free.
- **Bitstream** (§6): `ntt-core/bit.sh` runs the full Vivado-free Basys-3
  flow, timing-gated (every reported clock ≥ 50 MHz).

Table 5 lists the deliverables.

**Table 5. Deliverables and their certificates.**

| deliverable | file | contract | certified by |
|---|---|---|---|
| K-RED multiplier | `kred-butterfly/modular_mul_kred.v` | ports of `modular_mul.v`, latency 4 | `verify_kred.py` (z3, full domain), `fv_kred.sby` |
| verified butterfly | `kred-butterfly/compact_bf_v2.v` | ports/latency (6) of `compact_bf.v` | `fv_bf_v2_{ntt,intt}.sby` |
| ψ-fold twiddle ROM | `psi-fold-rom/tf_rom_fold.v` | interface of `tf_ROM.v` | `fv_rom_fold.sby` (every address) |
| complete core | `ntt-core/ntt_core.v` | host load/read, start/done | `fv_core.sby`, `run_check.py` |
| per-prime generator | `generator/kred_gen.py` | emits reducer RTL + checks | exhaustive (Kyber reducer) |
| verification harnesses | `verification/`, `*/fv_*.sby` | per-module, self-contained | 8-mutation sweep |

A `Dockerfile` provides a separate verification-only image (proofs and
simulations, pinned to a nixpkgs revision rather than the flake lock,
without the openXC7 flow). The numbers in this paper were taken from the
repository at commit `b0cf8da` (reference submodule `8373a66`); a Zenodo
DOI will be minted from the tagged release.
The single source for this paper (`docs/paper/paper.md`) builds to the
canonical two-column IEEEtran PDF (`make` in `docs/paper/`) and to a
single-column draft (`make draft.pdf`).

# Appendix A: the four lemmas

Paper proofs are short and live with the artifact (`docs/lemmas.md`);
the machine checks are the certificates. Throughout, q = k·2^m + 1 is a
Proth prime (k odd, k < 2^m), N = 2^n with 2N | q − 1, ψ a primitive
2N-th root of unity mod q, and `bitrev_n` the n-bit reversal; equalities
between residues are in Z_q.

**Lemma 1 (K-RED fold).** For all $z \ge 0$ with $z = z_1 2^m + z_0$,
$0 \le z_0 < 2^m$: `k·z₀ − z₁ ≡ k·z (mod q)`. Iterating F folds, with
multiple-of-q offsets keeping every term nonnegative, yields r ≡ k^F·z;
F and the offsets are chosen per prime so that r < 2q (two folds for
q = 12289 from z < 2²⁸; `kred_gen.py` computes the bound recurrence), and
one conditional subtraction finishes.
*Machine check:* `verify_kred.py` (z3, full 28-bit domain);
`generator/kred_gen.py` (Kyber, exhaustive z < q²).

**Lemma 2 (INTT-halving fusion).** If the ROM stores W = (k^F)⁻¹·w, the
forward multiply k^F·(v·W) = v·w is exact, and feeding op21(W) =
(2k^F)⁻¹·w to the inverse butterfly gives k^F·((v−u)·op21(W)) =
((v−u)·w)/2, the per-stage $\tfrac12$ the DIF-RN inverse requires, from the same
multiply. *Machine check:* `fv_bf_v2_intt.sby`, `run_stream.py`.

**Lemma 3 (ψ-fold).** For the bit-reversed layout
$w[i] = \psi^{\mathrm{bitrev}_n(i)}$ and $0 \le j < N/2$:
$w[N/2+j] = \psi \cdot w[j]$, recursing on sub-halves
($w[N/4+j] = \psi^2 \cdot w[j]$ for $0 \le j < N/4$, …). The negation
symmetry $\psi^{e+N} = -\psi^e$ of prior half-memory generators does not
apply: the stored exponents lie in [0, N) while ψ has order 2N, so no two
differ by N. For shift-friendly ψ the derived half is multiplier-free
(ψ = 7: `7x = (x<<3) − x`).
*Machine check:* `rom_fold_math.py`, `verify_rom_fold.py`,
`fv_rom_fold.sby` (9·RTL ≡ shipped ROM mod q at every legal address
A < 1023).

**Lemma 4 (composition).** Constant scalings mod q commute, so the
(k^F)⁻¹ ROM scaling and the ψ-fold coexist:
$\psi \cdot ((k^F)^{-1} w[j]) = (k^F)^{-1} w[N/2+j]$, and the
k^F-scaling butterfly restores exactly the specified transform.
*Machine check:* `rom_fold_math.py`, `run_stream.py` (end-to-end).

# Appendix B: verification obligations

The detail behind Figure 2; every row is re-run by CI on each push.

**Table 6. Verification obligations, methods and scopes.**

| property | method | scope |
|---|---|---|
| K-RED unit == k^F·a·b mod q | z3, divider-free congruence | full 28-bit domain |
| fold7 == 7·x mod q | z3, congruence | full domain (x<q) |
| 9·`tf_rom_fold` ≡ shipped `tf_ROM` (mod q) | SymbiYosys miter | after every enabled read of a legal address (A < 1023); outputs hold while REN is low |
| butterfly (NTT / INTT) == spec | SbY compositional, domain-faithful | u,v,w < q, mode fixed per harness, after the flush window; latency-exact |
| own-FSM control safety (§5) | SymbiYosys k-induction, datapath stubbed | arbitrary host behaviour, both modes; safety only |
| host writes reduced mod q | k-induction assert, h_din unconstrained | every host write, symbolic data |
| reset / power-up-X / single-clock | SymbiYosys + netlist audit | structural |
| non-vacuity | 8 RTL mutations | each kills its proof |
| streaming datapath INTT(NTT(x))=x | iverilog simulation | two seeded vectors, N=1024 |
| own core NTT / INTT vs independent golden | iverilog + golden, bijectivity | 4 round-trip + 2 inverse vectors incl. raw ≥ q, fresh dumps |
| generalization (Kyber q=3329 reducer) | exhaustive + iverilog | all z<q², generated RTL (60k vectors) |

# References

::: {#refs}
:::
