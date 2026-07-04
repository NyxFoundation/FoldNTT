# Formal lemmas (Phase 6)

The paper's claims rest on four lemmas. Each is stated here as a paper-ready
proposition with a paper proof, and cross-referenced to its machine-checked
counterpart in the repo (the machine check is the *certificate*, the paper
proof is for the reader).

Throughout: `q = k·2^m + 1` is a Proth prime, `N = 2^n`, ψ a primitive
2N-th root of unity mod q, and `bitrev_n` the n-bit reversal.

---

## Lemma 1 (K-RED fold). 
*For all integers z ≥ 0, writing z = z₁·2^m + z₀ with 0 ≤ z₀ < 2^m,*

    k·z₀ − z₁ ≡ k·z   (mod q).

**Proof.** k·z = k·z₁·2^m + k·z₀. Since q = k·2^m + 1, we have
k·2^m = q − 1 ≡ −1 (mod q), hence k·z₁·2^m ≡ −z₁, so
k·z ≡ k·z₀ − z₁ (mod q). ∎

**Corollary (F-fold reducer).** Applying the fold F times, each with a
non-negativity offset C_i that is a multiple of q, yields a value
`r ≡ k^F·z (mod q)`; choosing offsets and F so the magnitude drops below 2q
lets a single conditional subtraction finish. The spurious factor k^F is
absorbed by scaling the twiddle ROM by (k^F)⁻¹.

*Machine check:* `verify_kred.py` (Falcon, z3, full 28-bit domain, via the
nonnegative linear identities `3c+6q = d+c₁q`, `3d+q = e+d₁q`);
`kred_gen.py` (Kyber, exhaustive over z < q²; general F, offsets computed).

---

## Lemma 2 (INTT-halving fusion).
*Let the twiddle ROM store W = (k^F)⁻¹·w. Feeding the K-RED unit W for the
forward butterfly gives k^F·(v·W) = v·w exactly. Feeding it op21(W) =
(2·k^F)⁻¹·w for the inverse butterfly gives*

    k^F·((v−u)·op21(W)) = ((v−u)·w) / 2   (mod q),

*i.e. the per-stage ½ scaling required by the DIF-RN INTT is produced by the
same multiply, at zero extra multiplier cost.*

**Proof.** Direct: k^F·(v·(k^F)⁻¹·w) = v·w; and
k^F·((v−u)·(2·k^F)⁻¹·w) = (v−u)·w·2⁻¹, and 2⁻¹ mod q = (q+1)/2 so
multiplication by 2⁻¹ is exactly op21. ∎

This is why the released radix-2 core is wrong (upstream issue #7): it omits
this ½, so its INTT output is scaled by 2^n. The fix costs two op21 gates
(shift-add), one on the ROM output and one on the add path.

*Machine check:* `../kred-butterfly/fv_bf_v2_intt.sby` (RTL butterfly ≡ the
fused spec), `kred_math.py` and `../verification/fullcore/run_stream.py`
(full-transform round-trip exact).

---

## Lemma 3 (ψ-fold of the bit-reversed table).
*For the bit-reversed negacyclic layout w_rom[i] = ψ^{bitrev_n(i)}, and all
0 ≤ j < N/2,*

    w_rom[N/2 + j] = ψ · w_rom[j]   (mod q).

**Proof.** For j < N/2, bit n−1 of j is 0, so bitrev_n(j) is even and
bitrev_n(N/2 + j) = bitrev_n(j) + 1 (setting bit n−1 of the index maps to
bit 0 of the reversed exponent). Hence
w_rom[N/2+j] = ψ^{bitrev_n(j)+1} = ψ·w_rom[j]. ∎

**Corollary (recursion).** Iterating on the sub-halves,
w_rom[N/4+j] = ψ²·w_rom[j], etc.; storing N/2^ℓ words and deriving with ℓ
chained ψ-multiplies. **Crucially**, the negation symmetry
`ψ^{k+N} = −ψ^k` used by prior Half-Memory TFGs does *not* apply here,
because the bit-reversed exponents range over [0, N) with no two differing
by N; Lemma 3 is the structurally-available replacement.

**Corollary (multiplier-free for shift-friendly ψ).** If ψ has few set bits,
ψ·x is a shift-add sum; for Falcon ψ=7, 7x = (x<<3)−x. Then the derived half
needs no multiplier.

*Machine check:* `rom_fold_math.py` (relations at levels 1–3 vs the real
`tf_ROM.v`), `verify_rom_fold.py` (fold7 z3 full-domain),
`fv_rom_fold.sby` (RTL ≡ shipped ROM at every address).

---

## Lemma 4 (K-RED / ψ-fold composition).
*Constant scalings commute with both constructions, so the K-RED spurious
factor and the ψ-fold coexist: storing (k^F)⁻¹-scaled words in the folded
ROM and deriving the upper half by ψ-multiply yields, after the k^F-scaling
butterfly, exactly the reference transform.*

**Proof.** Both the ROM scaling by (k^F)⁻¹ and the ψ-fold are
multiplications by constants mod q; multiplication is associative and
commutative, so the derived word ψ·((k^F)⁻¹·w_rom[j]) = (k^F)⁻¹·(ψ·w_rom[j])
= (k^F)⁻¹·w_rom[N/2+j], which the k^F-scaling butterfly turns into
w_rom[N/2+j]·(operand) as required. ∎

*Machine check:* `rom_fold_math.py` (9⁻¹ composition) and
`../verification/fullcore/run_stream.py` (the folded ROM + K-RED butterfly
round-trip exact end-to-end).

---

## Note on the verification methodology (for the methods section)

Two techniques made the SMT proofs tractable and are worth stating:

1. **Divider-free congruence encoding.** Proving `r == z mod q` directly
   forces the solver to bit-blast a divider (`URem`), which diverges for
   28-bit operands. Instead we prove the *nonnegative linear identity*
   `k^i·z + C = r + q·(fold terms)` plus `r < q`; these are constant
   multiplications only and close in seconds. (This is the single change
   that turned a 2-hour non-converging run into an 11-second proof.)

2. **BMC-completeness for time-local pipeline properties.** Every assertion
   relates outputs to inputs at most `latency` cycles back, guarded by a
   saturating counter, with the initial register state unconstrained. A BMC
   of depth `guard + latency + 1` therefore covers every window of every
   execution — an unbounded proof without needing invariant discovery for
   k-induction. Non-vacuity is established separately by RTL mutation.
