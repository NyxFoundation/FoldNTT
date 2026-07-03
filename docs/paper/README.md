# Paper build

`paper.md` (GitHub-flavored Markdown) is the source of truth; `references.bib`
holds the bibliography. Build a PDF (or a LaTeX intermediate for a venue
template) with pandoc:

```sh
nix shell nixpkgs#pandoc nixpkgs#texliveSmall --command make        # paper.pdf
nix shell nixpkgs#pandoc --command make paper.tex                   # LaTeX only
```

The citekeys in the prose (`[cfntt]`, `[longa2016kred]`, …) are **readable
markers** that map 1:1 to entries in `references.bib`. This build produces a
plain PDF/LaTeX skeleton with the markers left as text. At submission,
convert to the venue's citation macros (TCHES has its own LaTeX class; FMCAD
uses IEEEtran) — replace each `[key]` with `\cite{key}` and let BibTeX/biber
render `references.bib`. The section structure maps 1:1 to a two-column
article.

Status: complete draft. Open items tracked in `../paper-plan.md` →
"Remaining before submission" (whole-core PnR/Fmax, Zenodo DOI at release,
venue choice, a couple of `[verify]` page numbers).
