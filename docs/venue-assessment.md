# Venue assessment & submission strategy

Where this work stands and where it should go. The goal is an *accepted*
paper, not a submitted one.

## Current level: submittable conference paper (FMCAD/DATE), with measured hardware

The individual technical ingredients are mostly known art. The value lies
in their integration, the formal verification, and a real bug find, not in
a new primitive. Specifically:

- K-RED reduction is not novel. Longa–Naehrig 2016 covers the software
  side; K-RED in hardware for Kyber exists (ePrint 2024/1890). Our use is a
  verified retrofit of a published accelerator, plus folding the factor to
  fix a bug: an engineering and verification contribution, not a new
  reduction.
- "Store half the twiddle table" is a known genre. Half-memory TFGs use
  the negation symmetry. Our bit-reversed ψ relation (multiplier-free,
  proven equal to the shipped ROM) is a distinct mechanism but an
  incremental one.
- Open-flow PnR now obtained (openXC7 nextpnr-xilinx, xc7a100t): real
  7-series area and post-route Fmax, per-module and whole-core. The numbers
  are not vendor-official Vivado, and there is no SOTA throughput
  comparison yet; those are the remaining hardware asks for a top HW venue.
- Whole-core functional timed run still open: the reconstructed FSM
  elaborates (area/Fmax valid) but is not yet cycle-accurate, so a functional
  full-core simulation of the banked schedule doesn't yet round-trip.

What is strong and defensible today:

- A real functional bug in a peer-reviewed accelerator's released RTL
  (missing per-stage INTT halving → 2¹⁰ scaling), found because we
  verified rather than tested, reported upstream, and fixed for free by the
  redesign.
- An end-to-end, CI-reproducible functional-verification methodology
  (exact-width SMT with a divider-free congruence encoding; compositional
  assume-guarantee; BMC-completeness; mutation-tested non-vacuity) applied
  to a whole published artifact down to its ROM contents.
- A verified, drop-in, multiplier-lean redesign (3→1 DSP/butterfly)
  that also halves twiddle storage, generalized by a generator and checked
  on Kyber exhaustively.
- Measured hardware payoff (open flow): the shipped whole core gets
  3→1 DSP, −14% FF, the bug fix and −50% twiddle bits at ≈1% Fmax cost
  (~137→~136 MHz). The butterfly's −26% dilutes because the memory system
  dominates the core's critical path.

## This is really two papers

| framing | best venues | current odds | what it needs |
|---|---|---|---|
| **Formal-methods case study** — verify a published PQC accelerator, find a bug, use verification to guide a multiplier-lean redesign | **FMCAD** (Applications track), DATE (verification), possibly a CAV tool/case-study | **Submittable now** (still the safest fit) | tighten the writeup |
| **Hardware design paper** — 1-mult K-RED butterfly + ψ-fold ROM, drop-in retrofit | DATE, ICCAD, ASP-DAC | **now viable** (was "needs PnR") — we have open-flow area **and** Fmax | a SOTA comparison table; Vivado confirmation strengthens but the open-flow numbers are defensible |
| same, top-tier | **TCHES / CHES** | still a stretch | vendor Fmax/throughput vs SOTA + a sharper novelty framing than "known primitives, integrated + verified" |
| **Agentic discovery** — an LLM inventing a verified HW optimization via visual 3D review in an RSI loop | MLCAD, LLM-for-EDA / LLM4HW workshops, arXiv | **workshop-viable** as its own paper | an ablation (visual vs code-only) |

**Update (open-flow PnR obtained).** The "Hardware design paper" row moved
from needs-PnR to viable: we now have real 7-series area (per-module and
whole-core) and post-route Fmax (openXC7 `nextpnr-xilinx`, xc7a100t). The
headline: the shipped core gets 3→1 DSP, the INTT bug fixed, and −50%
twiddle bits at ≈1% whole-core Fmax cost (the isolated butterfly's −26%
dilutes to ~1% because the memory system dominates). This is no longer a
paper without hardware numbers; it is a verified, measured retrofit.
Caveat for a top HW venue: the numbers are open-flow (nextpnr), not
vendor-official Vivado, and lack a head-to-head throughput comparison vs the
Kyber/Falcon SOTA. Those two additions are what separate a solid DATE/ICCAD
submission from a TCHES-competitive one.

## Recommendation

1. Safest target: FMCAD Applications track (or DATE verification). The
   "verify a real accelerator → find a real bug → verification-guided
   redesign, all reproducible in CI" narrative is complete, and the
   measured hardware is now strong supporting evidence.
2. Now viable: DATE/ICCAD (hardware framing). Open-flow area+Fmax exist
   (per-module + whole-core), and the paper has a quantitative positioning
   table (§7): vs the base, ENS −21% (Compact-FALCON's own metric) at equal
   function/Fmax; vs Compact-FALCON, a different-design-point note (they
   are ~8× faster per NTT but ~10× our ENS and do FFT too). Remaining
   polish: a fuller multi-accelerator table and optional Vivado
   confirmation. A cycle-accurate FSM would add a functional whole-core
   timed run.
3. Keep the agentic-discovery angle as a separate workshop paper, not a
   claim in the main paper, where it stays a single "how it was found"
   paragraph. A visual-vs-code-only ablation would make it a real
   contribution rather than an anecdote.
4. TCHES/CHES remains a stretch. The reduction is known art and the ROM
   trick is incremental. Even with the measured open-flow numbers, a top
   crypto-HW venue would want vendor Fmax, a throughput win vs SOTA, and a
   sharper novelty framing. Revisit only with those.

## One-line pitch, per venue

- FMCAD/DATE-verification: "We functionally verified a published TCHES
  PQC-NTT accelerator against its spec, found and reported an
  inverse-transform bug, and used the verification to guide a verified,
  multiplier-lean, bug-fixed redesign, reproducibly in CI."
- DATE/ICCAD-hardware: "A drop-in retrofit of a conflict-free NTT
  accelerator: 3→1 DSP and half the twiddle ROM at ≈1% whole-core Fmax cost,
  formally verified, with open-flow FPGA numbers, and an inverse-transform
  bug fixed along the way."
- Workshop (agentic): "An LLM invented a verified twiddle-ROM
  optimization by visually reviewing a 3D floor-plan model inside an
  automated verify-in-the-loop process."

## Bottom line

Two routes are open now:
- Safest: the FMCAD/DATE formal-methods case study. Lead with
  verify→bug→verification-guided-redesign; the measured hardware numbers are
  now a strong supporting result rather than a gap.
- Now viable: the DATE/ICCAD hardware paper. Lead with the measured retrofit
  (3→1 DSP, bug fix, −50% twiddle bits at ≈1% whole-core Fmax), with the
  verification as the reason to trust the drop-in. Add a SOTA throughput
  comparison table before submitting; Vivado confirmation is optional.

TCHES/CHES still needs vendor numbers and a sharper novelty story. Either
way, the verification-and-bug-find edge plus the now-complete measured
evaluation make this submittable; pick the framing by target venue.
