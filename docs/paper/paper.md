---
title: "Verified, Multiplier-Lean NTT Hardware for Proth Primes: a Formally-Checked Retrofit of a Conflict-Free Accelerator"
author: NyxFoundation
date: 2026
abstract: |
  We present a formally verified redesign of the released radix-2 CFNTT
  number-theoretic-transform accelerator (TCHES 2022) for the Falcon /
  FN-DSA prime q = 12289. (1) A *drop-in* butterfly that replaces the
  reference's three hardware multipliers with one via shift-add K-RED
  folds (q = 3·2¹²+1 is Proth), the residual factor folded into the
  twiddle ROM. K-RED itself is established, including in recent Kyber
  hardware; the delta is the *verified drop-in retrofit* — and the same
  fold *fixes a functional bug we found in the released RTL*: its inverse
  transform omits a per-stage halving and returns 2¹⁰·x (reported
  upstream). (2) A ψ-fold twiddle ROM storing half the words (recursively
  a quarter), the rest derived by one shift-sub gate from the bit-reversed
  negacyclic symmetry `w[N/2+j] = ψ·w[j]` — distinct from the negation
  symmetry of prior half-memory generators, which is structurally
  unavailable in this layout. (3) The verification methodology that found
  the bug: exact-width SMT with divider-free congruences, compositional
  proofs with domain-faithful abstractions, k-induction for control, and
  8-mutation non-vacuity, rerun by CI on every push. A parameterized
  generator instantiates the construction for other Proth primes — Kyber /
  ML-KEM q = 3329: reducer verified exhaustively, generated RTL by
  simulation sweep. On Artix-7 in a fully open flow: **3→1 DSP48 per
  butterfly and 50% fewer twiddle bits at ≈1% whole-core Fmax cost**, the
  inverse transform now correct; and — the released radix-2 control FSM
  being an empty file — a complete **own-FSM single-BFU core** whose
  control is proven by k-induction (data-independent control flow and
  latency; no leakage claim), running end-to-end to a timing-gated Basys-3
  bitstream.
---

<!-- Complete draft. Every number and claim traces to a CI-reproducible
     script (see the Reproducibility section). Builds to a single-column PDF
     (Makefile) and a two-column IEEE draft (ieee/), both clean. Remaining
     before a specific venue: \cite{} wiring against references.bib and the
     venue's class/page limit; a few references.bib entries carry
     [verify at camera-ready] notes for paywalled venue metadata. -->

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
  resulting constant factor into the twiddle ROM. K-RED is established in
  software NTTs and recently in Kyber hardware (§2); our contribution is
  not the reduction but the *verified, drop-in retrofit*, in which the
  same ROM fold repairs a **bug we found** in the released inverse
  transform (§3).

- **A ψ-fold twiddle ROM (§4.2), found by visual review.** The bit-reversed
  negacyclic table obeys `w[N/2+j] = ψ·w[j]`; with ψ shift-friendly (Falcon
  ψ = 7), half the ROM is derived by a shift-sub gate. This halves (recursively
  quarters) the stored words. The relation is distinct from the negation
  symmetry used by prior half-memory twiddle generators, which does not
  apply to bit-reversed tables.

- **A functional-verification methodology (§5)** that checks the *arithmetic
  and datapath against a mathematical specification* — as opposed to the
  masking/side-channel focus of recent PQC-hardware verification — down to
  the shipped ROM contents, reproducibly in CI. Its abstractions are
  *domain-faithful* (the solver, not a hand argument, discharges the
  assume-guarantee seams), its control proofs are inductive, and every
  proof is mutation-tested. This is not incidental: the inverse-transform
  bug surfaced *because* we verified rather than tested.

We show all three are instances of a construction that generalizes to any
Proth NTT prime, with a generator that emits and checks per-prime RTL
(§6), validated on Kyber (q = 3329) exhaustively. §7 reports costs measured
in an open FPGA flow (yosys + openXC7 `nextpnr-xilinx`, Artix-7): at the
whole core, **3→1 DSP per butterfly and half the twiddle storage at ≈1%
Fmax cost** (−21% on Compact-FALCON's ENS normalized-area metric, defined
in §7), with the inverse-transform bug fixed — no Vivado required. Because
the released **radix-2** core's control FSM is an empty file (upstream
issue #4; the radix-4 tree does ship one), we also build a complete
**own-FSM single-BFU core** from the verified blocks: its control is
proven safe by k-induction (§5), it round-trips exactly in
freshness-enforced simulation against an independent golden, and the same
open flow produces a Basys-3 self-test bitstream through a timing-gated
build (§7).

**Framing.** The through-line is *verify, don't just test*: a single
end-to-end functional check against the mathematical transform — which the
released design lacked — both **caught the bug** the shipped testbench
missed (§3) and **licensed the aggressive redesign**, since every change is
proven equivalent before it ships. The paper's primary contribution is this
verification-guided-design loop applied to a real, published accelerator;
the multiplier and ROM savings are its concrete payoff.

**Provenance.** The ψ-fold ROM was discovered by an
LLM coding agent while *visually reviewing a 3D floor-plan model* of the
architecture inside an automated view→implement→verify loop: with the
arithmetic shrunk by the K-RED step, the twiddle ROM was visibly the largest
remaining block, adjacent to shift-add fold stages and a reuse gate that
suggested the derivation. We report this because it is true and reproducible
(the full derivation history is public), not as a methodological claim; the
mathematics and proofs stand on their own.

# 2. Background

**Negacyclic NTT.** Lattice schemes multiply polynomials in the ring
`R_q = Z_q[x]/(x^N + 1)`. Naively this is an O(N²) convolution; the NTT
turns it into O(N log N) by evaluating at the powers of a primitive N-th root
of unity. The *negacyclic* wrap (the `x^N = −1` quotient) is handled by
pre/post-weighting with powers of ψ, a primitive **2N-th** root
(`ψ² = ω`, `ψ^N = −1`), so that a pointwise product in the transform domain
equals the negacyclic convolution back in `R_q`:
$a \cdot b = \mathrm{INTT}(\mathrm{NTT}(a) \odot \mathrm{NTT}(b))$. A radix-2
transform is a sequence of $\log_2 N$ stages of **butterflies**; the forward
pass uses decimation-in-time in natural-to-bit-reversed order (DIT-NR), the
inverse decimation-in-frequency in bit-reversed-to-natural order (DIF-RN),
which lets both share one bit-reversed twiddle table and avoids an explicit
reorder. The DIF-RN inverse butterfly additionally carries a per-stage
$\tfrac12$ scaling (the $N^{-1}$ of the inverse, distributed one factor of
$2^{-1}$ per stage), realized by a "multiply-by-$2^{-1}$" operator `op21` —
the operator the released radix-2 core omits (§3). For Falcon/FN-DSA,
`N = 1024`, `q = 12289`, and the reference uses `ψ = 7` (a primitive 2048-th
root mod q).

**The CFNTT accelerator.** CFNTT [TCHES 2022] is an in-place, memory-based
radix-2/4 NTT accelerator whose contribution is a **conflict-free memory
mapping**: coefficients are striped across **two banks** by the parity of
their address (bank = XOR of address bits, offset = address ≫ 1), and the
address generator emits, for every radix-2 stage, the pair of operands a
butterfly consumes. Because the two operands of any stage differ in exactly
the stage's bit, they always fall in different banks — so both are read (and
later written) in the same cycle with no bank conflict, keeping the single
pipelined butterfly fully fed. Twiddles come from **one shared ROM** of
`N − 1 = 1023` words in the bit-reversed layout `w[i] = ψ^{bitrev(i)}`, read
via a small twiddle-address generator whose sequence matches the stage/loop
counters. The released radix-2 RTL is what we retrofit; we leave its memory
system, address generators and conflict-free mapping untouched, changing only
the butterfly's arithmetic (§4.1) and the ROM's internals (§4.2).

**Modular reduction.** Barrett and Montgomery are the general-purpose
choices. For Proth primes q = k·2^m+1, K-RED `[longa2016kred]` reduces with shifts
and adds; established in *software* NTTs and, more recently, in Kyber
*hardware* (K-RED-Shift / Proth-ℓ, `[kredshift2024]`). Our use is a
*verified retrofit into a conflict-free accelerator*, with the factor folded
into the ROM and reused to fix the inverse transform.

**Twiddle storage.** Prior work reduces the ROM by on-the-fly generation
(a modular multiplier per butterfly) `[ntttool2025]` or by a *half-memory*
generator using the negation symmetry `W^{N/2} = −1` `[tfg2024halfmem]`.
Notably, the most recent Falcon NTT accelerator `[compactfalcon2025]`
stores its twiddles in full and reduces with Barrett — neither of our
contributions is present in it. We show a different symmetry, specific to
the bit-reversed negacyclic layout, that is multiplier-free.

**Verified PQC hardware.** The 2026 wave targets masking composition and
side-channel leakage (`[maskedntt2026a, maskedntt2026b]`). Functional
correctness of the arithmetic against a spec — our axis — is comparatively
underserved, and is what exposes logic bugs like the one in §3.

# 3. A bug in the released inverse transform

Because our methodology (§5) checks the RTL against the *mathematical*
transform rather than against a testbench, it surfaced a functional bug in
the released accelerator. We describe it in full: it is both a concrete
finding worth reporting and the clearest evidence for the "verify, don't
just test" thesis.

**The defect.** The DIF-RN inverse butterfly must apply a $\tfrac12$ scaling
*per stage* — the $N^{-1}$ of the inverse transform, distributed as one factor
of $2^{-1}$ each of the $\log_2 N$ stages (paper Alg. 3; the reference's own
Python model applies this as `op21`, $x\cdot 2^{-1}\bmod q = x(q{+}1)/2$). The
released radix-2 RTL **ships `modular_half.v` but instantiates it nowhere** in
`compact_bf.v`: in inverse mode (`sel=1`) the butterfly computes
$(u{+}v,\ (v{-}u)w)$ with no halving. The radix-4 PEs (`PE0–PE3.v`) *do*
instantiate `modular_half`, so the omission is specific to the radix-2 tree.

**Consequence.** Each inverse stage is a factor of 2 too large, so after
$\log_2 N = 10$ stages the radix-2 inverse output is scaled by
$\mathbf{2^{10}\bmod q}$: $\mathrm{INTT}(\mathrm{NTT}(x)) = 2^{10}x$, not $x$.
The forward transform is unaffected. There
is no partial cancellation — the map is linear, so the error is exactly a
global constant, which is why it is easy to miss by eyeballing a single
value and impossible to miss once checked against the spec.

**Why testing didn't catch it.** The shipped testbench (`tb_top.v`) has no
self-check: it drives stimulus and `$readmemb`s external files, with no
assertion on the result. There is also no reference vector committed. So the
design "runs" and produces output; nothing compares that output to
`INTT(NTT(x)) = x`. A single end-to-end functional assertion — the exact
thing our verification encodes — is all it would have taken.

**How we found and confirmed it.** The round-trip property
`INTT(NTT(x)) = x` failed in our SMT/simulation checks; the counterexample
was a clean global 2¹⁰ factor, which points directly at a missing per-stage
2⁻¹. We confirmed it bit-exactly at the **full-core RTL level** (`run_stream`
drives the shipped `compact_bf` through a complete N=1024 inverse and
reproduces `2¹⁰·x`), localized it to the un-instantiated `modular_half`, and
reported it upstream (issue #7; the empty control FSM `fsm.v` is the related
issue #4).

**The fix, and why it is free here.** Reinstating the halving normally costs
two `modular_half` gates per butterfly. In our K-RED redesign (§4.1) one of
them is absorbed at *zero* extra cost: the inverse twiddle is already derived
from the ROM word by an `op21` (to cancel the K-RED factor), and that same
`op21` supplies the multiply-path $\tfrac12$; only the add-path $\tfrac12$ needs an explicit
gate. So the multiplier-lean redesign and the bug fix are the same change
(Lemma 2). Our verified core round-trips exactly (§5, §7).

# 4. Design

The two inventions are drop-in: same ports, same delay fabric, same
latencies as the reference. Figure 1 is the proposed radix-2
butterfly; only the shaded blocks change. We cite four small algebraic
facts as Lemmas 1–4; they are stated in Appendix A, with paper proofs in
the artifact (`docs/lemmas.md`) and machine checks as the certificates.

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
  \node (w)  at (0,0)    {$w$};
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
reference. One \textbf{K-RED} multiplier replaces the reference's three; the two
\texttt{op21} ($\times\tfrac12$) gates --- one fused into the ROM word
(\texttt{modular\_half}), one on the INTT add path --- are the \S3 bug fix.
\texttt{sel}=0 (NTT) yields $(u{+}vw,\;u{-}vw)$; \texttt{sel}=1 (INTT) yields
$(\tfrac12(u{+}v),\;\tfrac12(v{-}u)\,w)$. Same ports, delays and latency as the
reference \texttt{compact\_bf}.}
\label{fig:datapath}
\end{figure*}
```

The multiplier is the single hardware multiply; the two `op21` (modular_half)
gates — one on the ROM word, one on the add path — are the §3 bug fix.

## 4.1 K-RED butterfly (invention 1)

**Reduction.** With z = z₁·2^m + z₀ and k·2^m ≡ −1 (mod q),
`k·z₀ − z₁ ≡ k·z` (Lemma 1). Two folds reduce a full product to < 2q:

    d = 3·z[11:0] + 6q − z[27:12]   ≡ 3z,   0 < d < 2¹⁷
    e = 3·d[11:0] +  q − d[16:12]   ≡ 9z,   0 < e < 2q
    r = e ≥ q ? e−q : e             =  9z mod q

`3x = (x<<1)+x`: shifts, adds, one conditional subtraction. Latency 4, ports
identical to `modular_mul.v` — one hardware multiplier (the product) instead
of three.

**Absorbing the factor 9.** Each fold multiplies the residue by k, so F
folds leave a spurious factor k^F — here k = 3, F = 2, i.e. 9. The ROM
stores W = 9⁻¹·w, so the forward
butterfly's `9·v·W = v·w` is exact; the inverse twiddle `op21(W)=(2·9)⁻¹·w`
is derived from the same word by one `modular_half`, and
`9·(v−u)·op21(W) = ((v−u)·w)/2` — **fusing the missing halving** (Lemma 2).
The add path gets one more `op21`. PWM (both operands data) double-passes the
unit with the stored constant 81⁻¹.

## 4.2 ψ-fold twiddle ROM (invention 2)

For the bit-reversed layout, `w[N/2+j] = ψ·w[j]` (Lemma 3), and ψ = 7 gives
`7x = (x<<3)−x`. So we store only the 512 lower (9⁻¹-scaled) words and derive
the upper half with a `fold7` gate — no multiplier, same interface and
latency as `tf_ROM.v`:

    t  = (base<<3) − base                       // 7·base ∈ [0, 7q)
    mq = (t ≥ 6q) ? 6q : (t ≥ 5q) ? 5q : … : (t ≥ q) ? q : 0   // 6 parallel cmps
    Q  = upper ? (t − mq)[13:0] : base          // one subtraction, < q

Six *parallel* constant comparators pick the multiple `mq` and a single
subtraction reduces — chosen over three chained conditional subtractions
after a logic-depth analysis (§7: LTP 31→26, area down, still DSP-free). The
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
obligation closes in seconds. The abstractions are **domain-faithful**: each
behavioural model returns an *unconstrained* value whenever an operand lies
outside the range its leaf proof justifies (`< q`), so the composite proof
can only pass if no leaf in the asserted cone ever sees an unreduced
operand — the assume-guarantee **domain seam is discharged by the solver**,
leaving no manual "operands stay reduced" argument in the trust base (and a
future edit that violates it becomes a counterexample, not a silently
unsound abstraction). Assertions are time-local with unconstrained
initial state, so a bounded model check of depth `guard+latency+1` is a
**complete** proof; reset and single-clock/CDC are checked structurally.

**Control, by induction (SymbiYosys).** The own-FSM core's control plane is
proven by **k-induction** with the datapath stubbed to unconstrained
sources: the invariants are the twiddle-counter closed forms
`rr = 2^(9−p) + k` (forward) and `rr = 2^(10−p) − 1 − k` (inverse), from
which the two external preconditions follow — every issued twiddle-ROM
address lies in the ROM's *proven* domain, and the two RAM write ports
never target the same address — together with the `busy`/`done` protocol,
under **arbitrary** host/start behaviour in both modes. Because the proof
holds with the data entirely unconstrained, it also establishes that
control flow and hence **transform latency are data-independent** (a
constant-time property at the control level). Host words are reduced mod q
on load (one conditional subtract suffices: a 14-bit word is < 2q), and the
proof asserts nothing unreduced enters the RAM.

**Non-vacuity.** Eight RTL mutations — a fold constant, a dropped halving
gate, a skipped twiddle mux, a corrupted ROM word, a wrong fold shift, a
swapped forward-butterfly subtraction operand, the abstraction's domain
guard disabled (proving the unconstrained-value mechanism is live), and a
mis-seeded FSM twiddle counter (the ROM address wraps out of domain) — each
make the corresponding proof fail with a counterexample; a kill only counts
on an actual counterexample, never on a harness crash.

**System level.** The real invented modules, driven through a full N=1024
NTT+INTT under iverilog, give `NTT(x)` = reference and `INTT(NTT(x)) = x`
exactly — the fix and the folded ROM compose correctly. (The reference core,
same harness, reproduces the 2¹⁰-scaled bug.) The complete own-FSM core is
checked the same way but stronger: multi-vector round-trips (including raw
14-bit inputs ≥ q, exercising the load reduction), the post-NTT memory
compared against an **independent Python golden** built from the shipped
`tf_ROM.v` table (so a common-mode bug in the shared RTL leaves cannot
pass), and the inverse validated by bijectivity
(`NTT_golden(INTT_rtl(y)) = y`). The harness enforces dump freshness —
every simulation artifact is deleted before and required after the run,
with simulator exit codes checked — a discipline adopted after a repository
reorganization silently disconnected an earlier cross-check.

Table 1 summarizes what is proven and how (all reproduced by CI on every
push).

**Table 1. Verification obligations and methods.**

| property | method | scope |
|---|---|---|
| K-RED unit == k^F·a·b mod q | z3, divider-free congruence | full 28-bit domain |
| fold7 == 7·x mod q | z3, congruence | full domain (x<q) |
| `tf_rom_fold` ≡ shipped `tf_ROM` | SymbiYosys miter | every address, any REN |
| butterfly (NTT/INTT) == spec | SbY compositional, domain-faithful | all inputs, latency-exact |
| own-FSM control safety (§5) | SymbiYosys k-induction, datapath stubbed | arbitrary host behaviour, both modes |
| host load reduced mod q | k-induction assert, h_din unconstrained | all 16384 words, symbolic |
| reset / power-up-X / single-clock | SymbiYosys + netlist audit | structural |
| non-vacuity | 8 RTL mutations | each kills its proof |
| full transform INTT(NTT(x))=x | iverilog simulation | random vectors, N=1024 |
| own core NTT / INTT vs independent golden | iverilog + golden, bijectivity | multi-vector incl. raw ≥ q, fresh dumps |
| generalization (Kyber q=3329) | exhaustive + iverilog | all z<q², generated RTL |

# 6. Generalization

All of §4 is parameterized by the Proth prime. A generator computes, per q:
the fold count and offsets, the spurious factor k^F and its inverse, `k·x`
as shift-adds, and the ψ-fold plan; it emits synthesizable RTL and checks
it. One caveat on scope: the K-RED leg applies to any Proth NTT
prime, but the ψ-fold's *multiplier-free* form additionally needs a
shift-friendly ψ (as in Falcon's ψ = 7); for a general q the fold becomes
a small constant multiply, which may not beat storing the words. We
validate **Kyber, q = 3329 = 13·2⁸+1** (ML-KEM) as an independent
instance: the K-RED reducer is checked *exhaustively* over all z < q²,
and the generated RTL passes a 60k-vector iverilog sweep (the RTL check is
a simulation sweep, not exhaustive). The generator even finds a tighter
Falcon schedule than our hand-written unit — evidence the construction
subsumes the special case.

# 7. Evaluation

We give technology-independent (generic gates), FPGA-primitive
(`yosys synth_xilinx`, 7-series) *and* post-route (openXC7 `nextpnr-xilinx`,
xc7a100t) counts; the latter two are what the claims rest on. Only
Vendor (Vivado) confirmation and physical on-board execution remain
outside CI (§9).

**FPGA primitives (Artix-7 target).**

| block | LUT | FF | **DSP48** | logic depth (LTP) |
|---|---|---|---|---|
| `modular_mul` (Barrett) → `modular_mul_kred` | 29 → 83 | 101 → **74** | **3 → 1** | 17 → 21 |
| `compact_bf` (ref) → `compact_bf_v2` | 158 → 231 | 297 → 270 | **3 → 1** | — |
| `tf_ROM` → `tf_rom_fold` | 241 → **192** | 14 → 15 | 0 → 0 | 7 → 26 |

Reading the numbers:

- **The headline is DSP: 3 → 1 per butterfly** (−67%), confirmed on real
  primitives, with −27% FF on the multiplier. NTT accelerators are
  DSP-bound (the DSP48 count scales with the number of parallel
  butterflies), so this is the resource that matters, and the saving scales
  ×d. The butterfly additionally becomes **inverse-correct**, fixing the §3
  bug at negative area cost in DSPs.
- **K-RED trades DSP for LUT/carry logic** (multiplier LUTs 29 → 83): a win
  on the usual DSP-bound design, roughly neutral on a LUT-bound one. We
  state both.
- **The twiddle ROM's win on FPGA is the −50% stored bits**, not a −79%
  logic cut: mapped to distributed LUT-ROM at N=1024 the fold saves
  ≈−20% LUT (241 → 192; fold7 adds logic); the stored-bit halving converts to a BRAM
  saving when the table is BRAM-mapped (larger N, or forced). The
  generic-gate count (−79%) overstates the distributed-ROM FPGA benefit.

**Timing (logic-depth proxy, `ltp`).** K-RED adds ~4 logic levels vs Barrett
(21 vs 17, both latency-4 pipelined; Barrett's DSP hides its own multiply
delay). The ψ-fold's real cost is **depth on the derived-half ROM read**
(LTP 26 vs 7 for a plain lookup): a logic-depth analysis drove a redesign of
`fold7` from three chained conditional subtractions to six parallel
comparators + one subtraction (LTP 31 → 26, LUT 214 → 192, still DSP-free,
re-verified). The measured Fmax cost is small (see the post-route Fmax
paragraph below); a pipelined fold7 would remove the ROM-read depth at
+1 latency.

**Whole-core area.** Synthesizing the entire core (one butterfly + two
conflict-free banks + twiddle ROM + address generators + FSM), reference vs
proposed, on 7-series primitives:

| core | LUT | FF | **DSP48** | RAMB18 |
|---|---|---|---|---|
| reference `top_poly_mul` | 784 | 582 | **3** | 2 |
| proposed `top_poly_mul_v2` | 824 | 502 | **1** | 2 |

DSP **3→1** at the core level (scaling ×d with parallel butterflies), FF
−14%, LUT +5% (the K-RED DSP→LUT trade slightly exceeds the ROM's LUT
saving), and **RAMB18 unchanged** — the two BRAMs are the data banks; both
twiddle ROMs map to distributed LUT-ROM, so the ψ-fold's −50% stored bits
does not cut BRAM count at N=1024 (it would at larger N or a forced
block-RAM ROM). This uses the reconstructed FSM to elaborate for synthesis
(area here; whole-core Fmax is measured separately below).

**A complete own-FSM core, through to a bitstream.** The released radix-2
core's control FSM is an empty file (upstream issue #4; the radix-4 tree
does ship one), which caps any radix-2 retrofit at the streaming/module
level. We therefore also package the
verified blocks into a minimal *complete* accelerator with our own
sequential single-BFU FSM (§5's induction proof): one `compact_bf_v2`, the
ψ-fold ROM, one dual-port BRAM, ≈74k cycles per 1024-point transform
(~1.5 ms at 50 MHz — a deliberately latency-modest design point; the
conflict-free streaming schedule above is the throughput story).
On `synth_xilinx` it maps to **1 DSP48 + 1 RAMB18 + ~600 LUT / ~186 FF** —
vast headroom on the smallest Basys-3 part (xc7a35t) — and the fully open
flow (yosys → openXC7 `nextpnr-xilinx` → prjxray `fasm2frames` →
`xc7frames2bit`) produces a working **on-board self-test bitstream** whose
build is **timing-gated** (every reported clock must close ≥ 50 MHz; the
core clock closes at 70–95 MHz across seeds). The on-chip self-test loads
`x[i] = 7i+1 mod q`, runs NTT then INTT, and reports
`INTT(NTT(x)) = x` on the LEDs; the same wrapper passes in simulation.

**Post-route Fmax (open flow, no Vivado).** Using openXC7's
`nextpnr-xilinx` + artix7 chipdb on xc7a100t, register-wrapped modules,
best of 3 seeds: `modular_mul` (Barrett) ~233 MHz vs `modular_mul_kred`
~230 MHz — **the K-RED multiplier is Fmax-neutral, so 3→1 DSP costs no clock
speed**; `compact_bf` (reference) ~164 MHz vs `compact_bf_v2` ~122 MHz
(−26%). The butterfly gap needs a caveat: the reference is partly faster
*because it is the buggy version* (it omits the §3 halving, so a correct
reference also pays for those gates), and the K-RED+op21 logic lengthens the
critical path vs a single DSP multiply. Net, the design trades DSP and
twiddle-memory for butterfly Fmax — the right trade on the DSP-/memory-bound
accelerators these actually are, and a pipelined fold recovers most of it at
+1 latency. (Vendor Vivado numbers would confirm but are not needed for this
conclusion.) **At the whole core** (`top_poly_mul` vs `top_poly_mul_v2`,
same elaborating core as the area numbers) the butterfly's −26% dilutes to
**~−1%**: ~137 vs ~136 MHz, because the conflict-free memory system, address
generators, networks and FSM — identical in both — dominate the critical
path. So the shipped core gets 3→1 DSP, −14% FF, the bug fix and −50%
twiddle bits at ≈1% Fmax cost.

**Positioning vs Falcon-NTT accelerators.** The two closest designs both
target q = 12289 and *both use Barrett with full twiddle ROMs* — neither of
our contributions appears in them:

| design | mult/bf | DSP | Fmax | NTT-1024 | ENS† | verified |
|---|---|---|---|---|---|---|
| CFNTT (base, our flow) | 3 | 3 | ~137 MHz | 5120 CC‡ / 37.4 µs | 969 | no |
| **this work** (streaming retrofit) | **1** | **1** | ~136 MHz | 5120 CC‡ / 37.6 µs | **769** | blocks proven (§5) |
| **this work** (own-FSM core, xc7a35t) | **1** | **1** | 70–95 MHz | ~74k CC / ~1.5 ms @ 50 MHz | — | **yes, runs** |
| Compact-FALCON | — | 20 | 134 MHz | 640 CC / 4.78 µs | ≈8143 | no |

(Designs cited in §8: CFNTT `[cfntt]`, Compact-FALCON `[compactfalcon2025]`;
the base's `no` is the §3 inverse-transform bug.)

†ENS = LUT/4 + FF/8 + BRAM×200 + DSP×100 (Compact-FALCON's own normalized
area metric), computed from the area tables above. All on Artix-7; ours/base
measured in the open flow (§7), Compact-FALCON as reported from Vivado —
different toolchains count LUTs differently, so the cross-design ENS is
indicative only; the load-bearing number is base→ours in one flow (−21%).
Compact-FALCON is a *combined FFT+NTT* accelerator (17395 LUT / 7950 FF /
20 DSP / 4 BRAM), hence its far larger ENS.

‡Architectural count for the streaming schedule (10 stages × 512
butterflies at 1 butterfly/cycle), identical in base and retrofit by the
drop-in construction — *neither* streaming core is cycle-exact-executable,
because the reference radix-2 FSM was never released (§9a). The own-FSM
row is the design point that actually executes: its cycle count is
measured and asserted by the artifact's `run_check.py`.

Two comparisons. **Against the base** (same architecture, our retrofit
target, same flow) the move is clean and rigorous: **ENS −21% (969→769)**,
driven by 3→1 DSP, at equal function and Fmax and with the §3 bug fixed — a
Pareto step on the DSP/twiddle-memory axes NTT cores are bound by.
**Against Compact-FALCON** we do *not* claim a throughput win: it is ~8×
faster per NTT (4.78 vs 37.6 µs) but that is a **different design point** — a
throughput-optimized *combined FFT+NTT* accelerator that is ~10× our ENS and
spends 20 DSPs. Ours is a minimal single-BFU DSP-lean NTT core whose edge is
DSP/area economy plus verification, not raw latency. A parallel-BFU
instantiation (the generator supports it) would trade our area lead for
throughput, but we do not measure that here.

# 8. Related work

**NTT accelerators and conflict-free memory.** In-place NTT hardware must
resolve the read/write bank conflicts of the butterfly access pattern; CFNTT
`[cfntt]` contributes a parity-based conflict-free mapping for radix-2/4,
which we retrofit. Other Falcon/Kyber accelerators
(`[compactfalcon2025, ntttool2025]`, and the mixed-radix EMINEM line) target
throughput or flexibility; the two closest Falcon-NTT designs both use
**Barrett reduction with full twiddle ROMs** (§7), so neither the K-RED
retrofit nor the ψ-fold appears in them.

**Modular reduction.** Montgomery and Barrett are the general-purpose
choices. K-RED `[longa2016kred]` exploits Proth primes `q = k·2^m+1` for a
shift-add reduction and is established in software NTTs; recent work brings
K-RED-style shift-add reduction to Kyber *hardware* (K-RED-Shift / Proth-ℓ,
`[kredshift2024]`). Our contribution is not the reduction but a **verified,
drop-in retrofit** of it into a published accelerator, with the residual
factor folded into the twiddle ROM and reused to repair the inverse
transform — i.e. reduction, scaling, and a bug fix unified in one change.

**Twiddle storage.** Prior art shrinks the twiddle ROM by *on-the-fly
generation* (a modular multiplier per butterfly) `[ntttool2025]` or by a
*half-memory* generator using the negation symmetry `W^{N/2} = −1`
`[tfg2024halfmem]`. The negation symmetry is **structurally unavailable in a
bit-reversed negacyclic table** (the stored exponents span `[0, N)` with no
two differing by `N`). The ψ-fold uses a different, address-halving relation
`w[N/2+j] = ψ·w[j]` specific to that layout, which for a shift-friendly ψ is
*multiplier-free*, recurses to a quarter, and is proven equal to the shipped
ROM at every address — properties the on-the-fly and negation-based schemes
do not jointly have.

**Verified PQC hardware.** The recent wave of machine-checked PQC-hardware
verification targets **masking and side-channel composition**
(`[maskedntt2026a, maskedntt2026b]`) — leakage properties, not functional
correctness of the arithmetic against a mathematical specification.
End-to-end *functional* verification of a whole published accelerator (down
to its ROM contents), of the kind that surfaced the §3 bug, is the
comparatively under-served axis this paper works on. Our SMT/BMC/mutation
toolkit uses standard techniques; the contribution is their *composition
into a reproducible, whole-artifact functional proof* and its use as a
design driver.

# 9. Limitations and future work

Whole-core **area** (LUT/FF/DSP/BRAM) and per-module **post-route Fmax** are
both now measured via the open flow (§7, openXC7 nextpnr-xilinx on
xc7a100t). Whole-core Fmax is also measured (~137 vs ~136 MHz) on the elaborating core
— static timing needs only the netlist. The functional whole-core gap is
closed by the own-FSM core (§7): it round-trips exactly with a proven-safe
FSM and builds to a bitstream. What remains: (a) the *reconstructed* CFNTT
FSM used to elaborate the streaming core for synthesis is still not
cycle-exact (superseded for functional claims by the own-FSM core, but the
original timed behaviour of the unreleased FSM stays unknowable); (b) the
own-FSM core is sequential — a pipelined 2-bank instantiation for
~1 butterfly/cycle is future work; (c) full-transform *formal* data-path
correctness remains compositional (proven blocks + proven control
invariants + freshness-enforced simulation against independent goldens) —
a ~150k-cycle end-to-end BMC is out of reach, and we state the boundary
rather than blur it; (d) physical on-board execution and vendor (Vivado)
confirmation of the open-flow figures are routine but outside CI; and
(e) power/EM side channels are out of scope (the k-induction proof gives
data-independent *latency*, §5, but says nothing about leakage). Generic
ψ-fold RTL emission and per-prime SymbiYosys generation are templated but
not yet automatic. The visual-discovery provenance is reported, not
evaluated (no ablation of the agent loop).

# 10. Conclusion

Starting from a released accelerator and *verifying* it, we found a real
inverse-transform bug, replaced its Barrett multipliers with a verified
Proth-prime K-RED unit that fixes the bug for free, halved its twiddle ROM
with a symmetry specific to bit-reversed negacyclic tables, and showed the
whole construction generalizes with a generator validated on Kyber.
Because the released radix-2 control FSM is an empty file, we closed the
loop ourselves: a complete own-FSM core built from the verified blocks, its
control proven by induction (with data-independent latency as a corollary),
running end-to-end to a timing-gated Basys-3 bitstream in a fully open
flow. Every number is reproducible from the public repository's CI.

# Reproducibility

Everything in this paper is public and CI-checked at
`github.com/NyxFoundation/FoldNTT` (the retrofitted RTL, the reference
CFNTT as a submodule, all proofs, the generator, the FPGA flow, and the
derivation history). A repo `flake.nix` pins the whole toolchain — including
the exact openXC7 tag — so `nix develop` drops into a shell where every
script below runs with no further setup. Each class of claim has a
one-command reproduction. The GitHub Actions workflow reruns the proof,
simulation and area classes on every push; the Fmax and bitstream flows are
one-command scripts under the same pinned toolchain but stay outside hosted
CI (the place-and-route chip database is too heavy for it):

- **Functional verification** — `run_all.sh`: the exact-width z3
  proofs (K-RED unit, fold7, generalization), the SymbiYosys proofs
  (butterfly miter with domain-faithful abstractions, ROM equivalence,
  own-FSM control safety by k-induction, reset/CDC, 8-mutation
  non-vacuity), and the iverilog full-transform round-trip.
- **Own-FSM core** (§5, §7) — `ntt-core/run_check.py`: freshness-enforced
  multi-vector round-trip, independent-golden NTT/INTT checks, and the
  streaming cross-validation; `ntt-core/fv_core.sby`: the control-safety
  induction proof.
- **Area** (§7) — `fpga/fpga_cost.sh` (per module) and
  `fpga_cost_core.sh` (whole core), via `yosys synth_xilinx`.
- **Post-route Fmax** (§7) — `fpga/fmax.sh` and `fmax_core.sh`, via
  **openXC7** `nextpnr-xilinx` on Artix-7 `xc7a100t`; no Vivado, no vendor
  download. The `flake.nix` pins the working openXC7 tag
  (`github:openXC7/toolchain-nix/0.8.2`) and exports `NP`/`CHIPDB`, so under
  `nix develop` both scripts run argument-free.
- **Bitstream** (§7) — `ntt-core/bit.sh`: the full Vivado-free Basys-3
  flow, timing-gated (every reported clock ≥ 50 MHz).

Both a `flake.nix` (`nix develop`) and a `Dockerfile` pin the whole toolchain
for artifact evaluation; a Zenodo DOI will be minted from the tagged release.
The single source for this paper (`docs/paper/paper.md`) builds to both a
single-column PDF and a two-column IEEE draft (`docs/paper/Makefile`,
`docs/paper/ieee/`).

# Appendix A: the four lemmas

Paper proofs are one-liners and live with the artifact (`docs/lemmas.md`);
the machine checks are the certificates. Throughout, q = k·2^m + 1 is a
Proth prime, N = 2^n, ψ a primitive 2N-th root of unity mod q, and
`bitrev_n` the n-bit reversal.

**Lemma 1 (K-RED fold).** For all $z \ge 0$ with $z = z_1 2^m + z_0$,
$0 \le z_0 < 2^m$: `k·z₀ − z₁ ≡ k·z (mod q)`. Iterating F folds (with
multiple-of-q offsets keeping terms nonnegative) yields r ≡ k^F·z with
r < 2q, finished by one conditional subtraction.
*Machine check:* `verify_kred.py` (z3, full 28-bit domain);
`generator/kred_gen.py` (Kyber, exhaustive z < q²).

**Lemma 2 (INTT-halving fusion).** If the ROM stores W = (k^F)⁻¹·w, the
forward multiply k^F·(v·W) = v·w is exact, and feeding op21(W) =
(2k^F)⁻¹·w to the inverse butterfly gives k^F·((v−u)·op21(W)) =
((v−u)·w)/2 — the per-stage $\tfrac12$ the DIF-RN inverse requires, from the same
multiply. *Machine check:* `fv_bf_v2_intt.sby`, `run_stream.py`.

**Lemma 3 (ψ-fold).** For the bit-reversed layout
$w[i] = \psi^{\mathrm{bitrev}_n(i)}$ and $0 \le j < N/2$:
$w[N/2+j] = \psi \cdot w[j]$, recursing on sub-halves
($w[N/4+j] = \psi^2 \cdot w[j]$, …). The negation symmetry
$\psi^{k+N} = -\psi^k$ of prior half-memory generators does not apply —
bit-reversed exponents span [0, N) with no two differing by N. For
shift-friendly ψ the derived half is multiplier-free (ψ = 7:
`7x = (x<<3) − x`).
*Machine check:* `rom_fold_math.py`, `verify_rom_fold.py`,
`fv_rom_fold.sby` (RTL ≡ shipped ROM at every address).

**Lemma 4 (composition).** Constant scalings mod q commute, so the
(k^F)⁻¹ ROM scaling and the ψ-fold coexist:
$\psi \cdot ((k^F)^{-1} w[j]) = (k^F)^{-1} w[N/2+j]$, and the
k^F-scaling butterfly restores exactly the reference transform.
*Machine check:* `rom_fold_math.py`, `run_stream.py` (end-to-end).

# References

Machine-readable entries in `references.bib`. Principal citations:

- **CFNTT** (the retrofitted accelerator): Chen, Yang, Yin, Wei, Liu,
  *CFNTT: Scalable Radix-2/4 NTT…*, TCHES **2022**(1):94–126,
  doi:10.46586/tches.v2022.i1.94-126. `[cfntt]`
- **K-RED** (reduction origin): Longa & Naehrig, *Speeding up the NTT…*,
  CANS 2016, LNCS 10052:124–139, ePrint 2016/504. `[longa2016kred]`
- **K-RED-Shift / Proth-ℓ** (K-RED in hardware): ePrint 2024/1890.
  `[kredshift2024]`
- **Half-memory / on-the-fly TFGs**: *Efficient Twiddle Factor Generators
  for NTT*, Electronics 13(16):3128, 2024 `[tfg2024halfmem]`; design tool
  ePrint 2025/1407 `[ntttool2025]`; *Compact FALCON FFT/NTT Accelerator*,
  IEEE 2025 `[compactfalcon2025]`.
- **Verified PQC hardware (masking line)**: arXiv:2604.15249, 2604.20793.
  `[maskedntt2026a, maskedntt2026b]`
- **Standards**: ML-KEM FIPS 203 `[fips203]`; Falcon / FN-DSA `[falcon]`.
- **Tools**: Yosys/SymbiYosys `[yosys]`, Icarus Verilog `[iverilog]`,
  Z3 `[z3]`.
