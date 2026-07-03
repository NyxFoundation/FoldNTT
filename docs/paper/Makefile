# Build the paper. Markdown is the source of truth (paper.md); this produces
# a PDF via pandoc + a LaTeX intermediate for the eventual venue template.
#   nix shell nixpkgs#pandoc nixpkgs#texliveSmall --command make
PANDOC ?= pandoc
FLAGS  = --from gfm --pdf-engine=xelatex -V geometry:margin=1in -V linkcolor:blue -V mainfont="DejaVu Sans" -V monofont="DejaVu Sans Mono"
# citekeys in the prose are readable markers ([cfntt], ...) resolving to
# references.bib; convert to \cite{} in the venue LaTeX class at submission.

paper.pdf: paper.md references.bib
	$(PANDOC) $(FLAGS) paper.md -o paper.pdf

paper.tex: paper.md references.bib
	$(PANDOC) $(FLAGS) --standalone paper.md -o paper.tex

clean:
	rm -f paper.pdf paper.tex

.PHONY: clean
