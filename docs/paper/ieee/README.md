# IEEE two-column build (submission skeleton)

Builds a two-column **IEEEtran** conference PDF from the single-source
`../paper.md`. IEEEtran is the format for DATE / ICCAD / DAC / ASP-DAC (the
hardware venues in `../../venue-assessment.md`), so this is a venue-neutral
starting point for the hardware-paper route.

```sh
# from docs/paper/ , with nix (pandoc + texliveFull):
nix shell nixpkgs#pandoc nixpkgs#texliveFull --command bash ieee/build.sh
# -> ieee/paper_ieee.pdf
```

## What works

Title, abstract, two-column body, section structure, references, Greek
letters and most inline symbols, and **all four data tables** (auto-converted
from pandoc `longtable` to both-column-spanning `table*` by `fix_longtables.py`
— longtable fails in two-column mode). Page 1 is submission-quality.

**Fig.1 is now a TikZ vector figure** (embedded in `../paper.md` as a
`{=latex}` raw block via `gfm+raw_attribute`, a both-column-spanning
`figure*` with `\resizebox`, so it renders in *both* the single-column and
two-column builds). The datapath, the shaded changed blocks, and both
adder/subtractor inputs all render cleanly in two columns.

## Remaining polish before submission-clean

1. **Verbatim/code width.** A few `verbatim` blocks (the K-RED equations and
   the fold7 pseudocode) still overflow the 3.5in column even at
   `\scriptsize` (they are long single lines). Either wrap/shorten them, set
   the widest ones as full-column-spanning listings, or move a couple of
   long derivations to prose. Cosmetic; content is legible.
2. **Equation-dense prose spacing.** A few paragraphs with clustered Unicode
   super/subscripts (mapped to math via `newunicodechar` in `preamble.tex`)
   lose some inter-word spacing. The clean fix is converting those inline
   Unicode expressions to proper LaTeX math in the source (`$2^{-1}$`,
   `$N^{-1}$`), which improves both builds.

Neither is on the critical path for the results (all measured/verified numbers
are in the CI-reproducible scripts and the single-column PDF); both are
ordinary camera-ready formatting, best done once a venue (hence the exact
class/format) is chosen.

## Files
| File | Role |
|---|---|
| `build.sh` | pandoc → IEEEtran → post-process → xelatex |
| `preamble.tex` | IEEEtran tweaks: mono font for Fig.1, Unicode→LaTeX maps |
| `fix_longtables.py` | longtable → two-column-spanning `table*` |
