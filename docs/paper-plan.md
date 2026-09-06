# Paper plan: status tracker

Goal: a submission-ready manuscript on the verified CFNTT improvements
(CFNTT-KRED butterfly + psi-fold twiddle ROM), the verification methodology,
and the upstream bug find. Working target venue: TCHES (fallback: FMCAD
case study). Every phase lands in docs/ as it completes.

| # | Phase | Output | Status |
|---|-------|--------|--------|
| 1 | Related-work sweep (novelty check: K-RED in hardware, twiddle generation/compression, verified NTT hardware, Falcon q=12289 accelerators) | `docs/related-work.md` | DONE (deep-read TODOs listed inside) |
| 2 | Novelty assessment; adjust claims | claims section in `docs/related-work.md` | DONE (C1-C3 adjusted) |
| 3 | FSM reconstruction + full-core RTL simulation (verilator) vs golden polymult | `verification/fullcore/` + `docs/evaluation.md` §sim | DONE (stream sim PASS; banked-FSM recon = future work) |
| 4 | Synthesis numbers (yosys synth_xilinx open flow; PnR if toolchain available) | `docs/evaluation.md` §synth | DONE generic; PnR = TODO |
| 5 | Generalization: parameterized generator (Proth-prime q → KRED constants + folded ROM + auto-proofs; Kyber q=3329 as second instance) | `generator/` + `docs/generalization.md` | DONE (Falcon+Kyber, Kyber exhaustive + RTL) |
| 6 | Formal lemma write-ups (psi-fold lemma, K-RED bounds) | `docs/lemmas.md` | DONE (4 lemmas, numerically re-checked) |
| 7 | Manuscript draft (abstract → intro → background → design → verification → evaluation → related → conclusion) | `docs/paper/paper.md` | DONE (full draft; section TODOs + refs inline) |

Ground rules: keep the novelty framing accurate (K-RED is Longa–Naehrig 2016
known art; the verified hardware fusion + psi-fold + bug-find + methodology
are the claims to defend); every number in the paper must be reproducible
from this repo's CI or scripts.


## Remaining before submission (post-draft)
- arXiv pre-submission review pass (2026-09-06): DONE. Fixed the K-RED
  hardware-precedent attribution (ePrint 2024/1890 is FHE-sized moduli,
  K2-RED-Shift; the Kyber precedent is Bisheh-Niasar et al. ARITH 2021, now
  cited), completed every bib author list (Tosun et al., Im et al., Dam et
  al. ISCAS 2025, Krieger et al., Iskander & Kirah), wired real citations
  (pandoc [@key] -> \cite{} + IEEEtran.bst; citeproc in the draft build),
  unified the "bug fix is free" claim to "two op21 gates, no added
  multiplier/latency", added the "bug vs unnormalized inverse" paragraph in
  Sec 3, restated data-independent latency as structural (not a theorem of
  the k-induction proof), split Table 4's "verified" column, disclosed the
  PWM double-pass cost (~6% on a full poly-mul), made Table 2 the planner's
  own output (signed-digit costs in kred_gen.py), and removed the
  glossary parentheticals / self-evaluative phrasing / "invention" /
  "Visioned Vibe Coding" naming. Two Codex CLI review rounds applied on
  top: proof scope narrowed everywhere (blocks + control-safety proven,
  composition simulated), whole-core area/Fmax labelled a synthesis-and-
  timing study on the non-cycle-exact reconstructed FSM (run_sim.py does
  not yet pass), §3 evidence corrected (bug_intt_halving.py models, not
  run_stream), Kyber limited to the reducer (incomplete NTT), PWM marked
  not-in-RTL, fixed the SMT identity (3z+6q = d+z1 q), added the inverse-
  twiddle identity, cited Casas et al. DAC 2023, fmax.sh/fmax_core.sh
  root-path bug fixed + per-seed logs archived + fail on tool failure,
  run_all.sh now covers run_stream/run_check/generator, flake pins sby +
  yices, table notes ride inside the IEEE floats.
  Author decisions taken: title changed to "... NTT Core with Formally
  Verified Arithmetic ..."; design-loop gallery URL added
  (visually-3d.kingmasatojames.workers.dev/#/s/ntt-fpga); abstract
  compressed to ~190 words.
- fsm_recon cycle-accuracy: DONE (2026-09-06). Root causes were (1) wen at
  pipe[9] instead of pipe[7] (write address/select/data all align at
  issue+8 in the shipped datapath) and (2) a testbench race: $readmemh in a
  posedge time step vs data_bank's per-cycle bank[A1] <= bank[A1] refresh
  left address 0 of both banks X (which the pipe[9] shift had masked).
  run_sim.py now passes on 5 vectors: ref NTT exact + INTT 2^10-scaled
  (issue #7 at full-core RTL), v2 exact, 5290 cycles launch-to-done,
  data-independent, ref == v2. Codex review: wen/pipe[7], phantom issue,
  drain (min 7, 16 kept), intra-stage disjointness all PASS; applied its
  asks (all tb actions on negedges, launch-to-done cycle markers, dump
  freshness + 512-word checks, conf-hold contract documented). CI + run_all
  now run run_sim.py. Re-measured under the flake's pinned yosys 0.62 +
  openXC7 0.8.2: per-module area/Fmax unchanged (243/232, 169/123 MHz);
  whole core 784/580 vs 819/500 LUT/FF (DSP 3->1), ENS 969->767 (-21%),
  Fmax 143.1 vs 137.5 MHz best-of-3 (-4%; seeds 127-143 / 130-138, medians
  136/134), NTT-1024 = 5290 cycles (launch-to-done, race-free negedge sampling; = 10 x (512+17)) = 37.0 / 38.5 us. Paper, evaluation.md,
  README refreshed; "~1% Fmax" claims replaced by "a few percent, within
  seed spread".
- Paper polish: DONE this pass. Fig.1 butterfly datapath (ASCII), fold7
  parallel-reduction pseudocode in Sec 4.2, and a positioning table vs
  CFNTT / Compact-FALCON in Sec 7 (both Barrett + full ROM; neither of our
  optimizations present).
- Paper builds: DONE. docs/paper/Makefile (pandoc -> PDF via xelatex, clean,
  no missing glyphs) + build README; CI generates the LaTeX skeleton on every
  push.  Citekeys are readable markers -> \cite{} at venue conversion.
- Sec 5 verification-summary table (Table 1) added.
- Editorial QA pass: reconciled the fold7-redesign numbers everywhere
  (ROM LUT 214->192 / -11%->-20% was stale in the prose + evaluation.md
  table after the parallel-reduction fold7); fixed 3 stale section refs
  (future-work was §8 pre-Related-Work-insertion, now §9); FF %s re-checked
  (mult -27%, core -14%, ROM -20% all consistent with the scripts).
- FSM reconstruction: partial progress. Traced the datapath, fixed the
  write latency (8->10, pipe[9]) to remove X-corruption; result now
  well-defined but not yet cycle-accurate (twiddle/network alignment).
  Whole-core area unaffected (elaborates); streaming sim still passes.
  Full cycle-accuracy remains future work (needed only for timed run/Fmax).
- Dedicated Related Work section (Sec 8) added to the paper body,
  consolidating docs/related-work.md: NTT accelerators / conflict-free
  memory, modular reduction, twiddle storage, verified PQC hardware, with
  each contribution positioned plainly against the prior art.
- §2 Background prose (NTT/CFNTT paragraph): DONE.
- Bibliography: DONE (docs/paper/references.bib; paper References section
  uses citekeys). A few paywalled page-numbers marked [verify at camera-ready].
- Compact-FALCON diff: DONE; full text read (PDF at docs/refs/, gitignored).
  It has no twiddle compression (the earlier attribution was a
  search-summary error), stores full FP64 twiddle ROMs + Barrett NTT
  reduction, xc7a100t @134MHz.  Neither of our contributions overlaps it;
  strengthens novelty (the latest Falcon-NTT is still full-ROM + Barrett).
- Whole-core area: DONE (fpga/fpga_cost_core.sh): DSP 3->1, FF -14%,
  LUT +5%, BRAM unchanged.
- Post-route Fmax: DONE without Vivado (openXC7 nextpnr-xilinx on xc7a100t,
  fpga/fmax.sh): multiplier Fmax-neutral (K-RED ~230 vs Barrett
  ~233 MHz -> 3->1 DSP for free); butterfly ~122 vs ~164 MHz (-26%, partly
  the cost of the #7 correctness fix). The DSP/memory-for-Fmax tradeoff is
  now stated in paper Sec 7/9 + abstract.
- Whole-core Fmax: DONE (fpga/fmax_core.sh): ~137 vs ~136 MHz -1%;
  the butterfly's -26% dilutes to ~1% at the core (memory/network/FSM
  dominate).  So the shipped core gets 3->1 DSP + bug fix + -50% twiddle
  bits at ~1% Fmax cost.  Remaining: cycle-accurate FSM for a functional
  timed run + optional Vivado confirmation.
- PDF render QA: fixed the positioning table overflowing the page (11->7
  cols; the 3 rightmost columns were silently clipped off-page), and cleared
  stale "Fmax needs Vivado/future work" lines in Sec 7 that contradicted the
  measured Fmax paragraph.  Full PDF builds clean (9pp, xelatex).
- IEEE two-column build skeleton (docs/paper/ieee/): pandoc->IEEEtran with
  a longtable->table* post-process; compiles as a 2-col conference PDF
  (DATE/ICCAD/DAC/ASP-DAC format), page 1 submission-quality.  Two documented
  Fig.1 is now a TikZ vector figure (both-column-spanning figure* via
  gfm+raw_attribute), rendering cleanly in both single- and two-column
  builds; a major look upgrade over the old ASCII art.
- Equation-dense prose (Sec 2/3) converted from inline Unicode to proper
  LaTeX math -> the IEEE 2-col build now compiles with zero errors and zero
  overfull boxes (and both builds read better).  IEEE build is submission-
  clean; only \cite{} wiring + venue class remain (mechanical).
- Reproducibility section upgraded from a 2-line stub to a concrete artifact
  statement: per-claim one-command reproduction (run_all.sh / fpga_cost*.sh /
  pnr/fmax*.sh), all CI-checked, all referenced scripts verified to exist,
  Docker + Zenodo-on-release noted.  Leverages the paper core strength.
- Key infra finding: Vivado is not required for routed Fmax; openXC7
  toolchain-nix (pin tag 0.8.2) gives it fully in nix.
- Dockerfile + CITATION.cff + docs/artifact.md: DONE; Zenodo DOI = at release.
- FPGA-primitive cost table (open flow, fpga/fpga_cost.sh): DONE; corrected
  the ROM claim (−79% was generic gates; FPGA distributed-ROM is −11% LUT /
  −50% bits) and the DSP-for-LUT tradeoff in evaluation.md + paper §7.
- Vivado-on-NixOS setup guide (docs/vivado-nixos.md): DONE; PnR run still TODO.
- Open-flow FPGA-primitive + logic-depth (ltp) numbers: DONE (fpga/fpga_cost.sh).
  Depth analysis drove a fold7 redesign (3 chained subs -> parallel compare +
  1 sub; LTP 31->26, area down, DSP-free), fully re-verified.
- Bibliography + Compact-FALCON diff: DONE (docs/paper/references.bib).
- Venue: see docs/venue-assessment.md. Current level = workshop/
  preprint; best-fit submittable-now target = FMCAD Applications / DATE
  verification (lead with the verify->bug->redesign story). TCHES needs the
  Vivado-PnR upgrade + SOTA comparison first.
