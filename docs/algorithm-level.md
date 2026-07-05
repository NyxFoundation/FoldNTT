# Algorithm-level implications

The paper deliberately claims hardware results only. This note records
where the same ideas apply *outside* hardware — in software
implementations and, most usefully, in protocol parameter selection.
Nothing here is in the paper's claim set.

## The observation

Both inventions are algebraic identities, not circuits:

- K-RED fold (Lemma 1): `k·z₀ − z₁ ≡ k·z (mod q)` for `q = k·2^m + 1`.
- ψ-fold (Lemma 3): `w[N/2+j] = ψ·w[j]` in the bit-reversed negacyclic
  twiddle table.

Identities are substrate-independent; whether they pay depends on the
cost model. Hardware pays because multipliers are the scarcest resource.
The software contexts below share that shape.

## Where K-RED pays in software

K-RED started as a software technique (Longa–Naehrig 2016), so this is
less a port than a map of where it still wins:

- **Embedded cores** (Cortex-M0/M4 class): narrow multipliers make the
  Barrett/Montgomery multiply chains expensive; shift-add folds are the
  same trade the FPGA makes.
- **Masked (side-channel-protected) implementations**: masking a linear
  operation costs linearly in the share count, masking a multiplication
  quadratically. Replacing two multiplies per butterfly with shift-adds
  is the hardware win re-priced in masking cost — plausibly larger, and
  unmeasured as far as we know.
- **ZK fields**: the Goldilocks reduction used by ZK provers is exactly
  this fold shape (k = 2³² − 1, signed-digit weight 1 subtraction), and
  `k^F ≡ 1 (mod q)` there, so no scaling correction is needed at all
  (§4.3 of the paper, Table 2).

On a desktop CPU with a full 64-bit multiplier, the win mostly vanishes.

## Where ψ-fold pays in software

Software NTTs store the same bit-reversed tables, so halving (recursively
quartering) transfers directly, at one constant multiply (or, for
shift-friendly ψ, a shift-subtract) per derived access:

- **Flash/ROM-constrained targets**: hundreds of bytes per table; modest
  but free.
- **GPU FHE libraries**: tables exist per RNS prime, dozens of primes,
  N up to 2¹⁶ — megabytes of twiddles whose traffic competes with data
  for memory bandwidth, which is the usual NTT bottleneck on GPUs. The
  ψ-fold is a middle point between storing everything and full
  on-the-fly generation: half (or quarter) the table for one constant
  multiply per derived access.

## The most useful transfer: parameter selection

The fold-economics boundary (paper §4.3) is a *selection criterion* for
anyone choosing new NTT primes (FHE RNS chains, new protocol
parameters):

> Prefer `q = k·2^m + 1` with the signed-digit weight of k at most 2
> (k = 2^a ± 1), and check whether a shift-friendly ψ exists for the
> target N.

Both properties cost nothing at the protocol level and make every future
implementation — hardware and software — cheaper. `generator/prime_scout.py`
enumerates the candidates:

```
uv run generator/prime_scout.py
```

Findings from the current sweep (14–16, 28–32 and 60–64 bit windows,
m ≥ 12):

- Cheap-fold primes are plentiful: every window has many `2^a ± 1`
  candidates with F = 2–3 folds, including the classics — Falcon 12289,
  BabyBear `15·2²⁷+1`, the FFT primes `3·2³⁰+1` and `127·2²⁴+1`-class
  entries, and Goldilocks (F = 3, no scaling needed).
- The scarce property is the **shift-friendly ψ**, not the cheap fold:
  in the sweep, only Falcon's q = 12289 has a signed-digit-weight-≤2
  primitive 2048-th root among small candidates (ψ = 7). Everywhere
  else the ψ-fold still works but needs a constant multiply instead of
  a shift-subtract — cheap in software, a real multiplier in hardware.
  A protocol that wants the multiplier-free fold must select for it
  explicitly.

## What does not transfer

- No asymptotic change: the transform stays O(N log N) with the same
  schedule; these are constant-factor, representation-level savings.
- Desktop-CPU scalar code: multipliers are effectively free there.
- All software claims above are cost-model arguments, not measurements;
  none of them is validated by this repository's CI. Treat this note as
  a map of where measuring would be worthwhile.
