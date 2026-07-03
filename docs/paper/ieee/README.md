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

## Two documented tasks before it is submission-clean

1. **Fig.1 needs a vector redraw.** It is currently an ASCII/box-drawing
   diagram (~78 columns wide); that fits the single-column `../paper.pdf` but
   **cannot fit a 3.5in IEEE column** (it overflows ~600pt even at
   `\scriptsize`). Redraw it in TikZ (or as an included PDF) for the
   two-column format. The single-column `make -C .. paper.pdf` build renders
   it fine in the meantime.
2. **Equation-dense prose spacing.** A few paragraphs with clustered
   Unicode super/subscripts and `−`/`½`/`2⁻¹` (mapped to math via
   `newunicodechar` in `preamble.tex`) lose inter-word spacing. The clean fix
   is to convert those inline Unicode expressions to proper LaTeX math in the
   source (`$2^{-1}$`, `$N^{-1}$`) — or add a pandoc Lua filter — rather than
   rely on character remapping. This does not affect the single-column build.

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
