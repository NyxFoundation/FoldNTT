# Paper build

`paper.md` (GitHub-flavored Markdown) is the source of truth; `references.bib`
holds the bibliography. Build a PDF (or a LaTeX intermediate for a venue
template) with pandoc:

```sh
nix shell nixpkgs#pandoc nixpkgs#texliveFull --command make          # paper.pdf (two-column IEEE)
nix shell nixpkgs#pandoc nixpkgs#texliveSmall --command make draft.pdf  # single-column serif draft
nix shell nixpkgs#pandoc --command make paper.tex                    # LaTeX only
```

Citations in the prose are pandoc markers (`[@cfntt]`, `[@longa2016kred]`,
…) resolving to `references.bib`. The IEEE build emits `\cite{}` and runs
BibTeX with `IEEEtran.bst`; the single-column draft uses pandoc's citeproc.
TCHES has its own LaTeX class; the section structure maps 1:1 to a
two-column article either way.

Status: complete draft, revised after an arXiv pre-submission review pass
(2026-09-06; see `../paper-plan.md`). Open items before submission: Zenodo
DOI at release, venue choice, and the limitations listed in paper §8.
