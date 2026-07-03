# Venue assessment & submission strategy (honest)

A candid read of where this work stands and where it should go. Written to
avoid self-deception: the goal is an *accepted* paper, not a submitted one.

## Current level: workshop / preprint, trending to a conference case study

The individual technical ingredients are mostly known art; the value is in
their **integration, formal verification, and a real bug find**, not in a
new primitive. Specifically:

- **K-RED reduction is not novel.** Longa–Naehrig 2016 (software); K-RED in
  hardware for Kyber exists (ePrint 2024/1890). Our use is a *verified
  retrofit* of a published accelerator + folding the factor to fix a bug —
  an engineering + verification contribution, not a new reduction.
- **"Store half the twiddle table" is a known genre.** Half-memory TFGs use
  the negation symmetry. Our bit-reversed ψ relation (multiplier-free,
  proven equal to the shipped ROM) is a *distinct mechanism* but an
  *incremental* one.
- **No FPGA place-and-route / Fmax yet** — the headline metric for a
  hardware paper is missing (open-flow LUT/DSP/logic-depth only).
- **Whole-core integration incomplete** (the banked-memory FSM
  reconstruction is not cycle-accurate).

What IS genuinely strong and defensible today:

- A **real functional bug** in a peer-reviewed accelerator's released RTL
  (missing per-stage INTT halving → 2¹⁰ scaling), found *because* we
  verified rather than tested, reported upstream, and fixed for free by the
  redesign.
- An **end-to-end, CI-reproducible functional-verification methodology**
  (exact-width SMT with a divider-free congruence encoding; compositional
  assume-guarantee; BMC-completeness; mutation-tested non-vacuity) applied
  to a whole published artifact down to its ROM contents.
- A **verified, drop-in, multiplier-lean redesign** (3→1 DSP/butterfly)
  that also halves twiddle storage, generalized by a generator and checked
  on Kyber exhaustively.

## This is really two papers

| framing | best venues | current odds | what it needs |
|---|---|---|---|
| **Formal-methods case study** — verify a published PQC accelerator, find a bug, use verification to guide a multiplier-lean redesign | **FMCAD** (Applications track), DATE (verification), possibly a CAV tool/case-study | **Submittable ~now** (best fit) | tighten the writeup; the story already holds without heavy PnR |
| **Hardware design paper** — 1-mult K-RED butterfly + ψ-fold ROM, drop-in retrofit | DATE, ICCAD, ASP-DAC | **B→A tier WITH PnR** | real Vivado Fmax + SOTA comparison on the CFNTT part |
| same, top-tier | **TCHES / CHES** | **likely reject as-is** | PnR + beat/match SOTA throughput + sharper novelty than "known primitives, integrated" |
| **Agentic discovery** — an LLM inventing a verified HW optimization via visual 3D review in an RSI loop | MLCAD, LLM-for-EDA / LLM4HW workshops, arXiv | **workshop-viable** as its own paper | an ablation (visual vs code-only), and framing as a methods contribution |

## Recommendation

1. **Primary target: FMCAD Applications track (or DATE verification).** The
   "verify a real accelerator → find a real bug → verification-guided
   redesign, all reproducible in CI" narrative is honest, complete, and
   defensible *today*. This plays to the work's actual strength (functional
   verification + a concrete find) rather than to hardware performance we
   haven't measured.
2. **Upgrade path to DATE/ICCAD (hardware framing):** get the Vivado PnR
   numbers (`docs/vivado-nixos.md`), finish the FSM so whole-core numbers
   exist, and add a SOTA comparison table. Only then is a design-conference
   or TCHES submission defensible.
3. **Keep the agentic-discovery angle as a separate workshop paper**, not a
   claim in the main paper (where it stays one honest "how it was found"
   paragraph). A visual-vs-code-only ablation would make it a real
   contribution rather than an anecdote.
4. **Do not target TCHES/CHES with the current content.** The reduction is
   known, the ROM trick is incremental, and there are no silicon/PnR
   numbers; it would very likely be rejected. Revisit after the hardware
   upgrade path above.

## Honest one-line pitch, per venue

- **FMCAD/DATE-verification:** "We functionally verified a published TCHES
  PQC-NTT accelerator against its spec, found and reported an
  inverse-transform bug, and used the verification to guide a verified,
  multiplier-lean, bug-fixed redesign — reproducibly in CI."
- **DATE/ICCAD-hardware (post-PnR):** "A drop-in retrofit of a conflict-free
  NTT accelerator: 3→1 DSP per butterfly and half the twiddle ROM, at equal
  function, formally verified, with FPGA numbers."
- **Workshop (agentic):** "An LLM invented a verified twiddle-ROM
  optimization by visually reviewing a 3D floor-plan model inside an
  automated verify-in-the-loop process."

## Bottom line

Right now: **arXiv preprint + FMCAD/DATE case-study submission** is the
honest, achievable move. TCHES-level requires the PnR upgrade and a sharper
novelty story. The verification-and-bug-find framing is the paper's real
edge; lead with it.
