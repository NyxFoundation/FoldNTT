#!/usr/bin/env bash
# Build the arXiv submission package from the single-source paper.md:
#   docs/paper/arxiv/            staging dir (main.tex, main.bbl, references.bib,
#                                discovery-timeline.png, 00README.json)
#   docs/paper/foldntt-arxiv.zip the upload
# The package is test-compiled standalone with xelatex (no bibtex: arXiv uses
# the shipped main.bbl) before zipping.  Select "xelatex" as the processor
# when uploading (00README.json also says so).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); paper=$(cd "$here/.." && pwd); root=$(cd "$paper/../.." && pwd)
bash "$here/build.sh" >/dev/null
out="$paper/arxiv"; rm -rf "$out"; mkdir -p "$out"
sed -e 's|{\.\./\.\./assets/discovery-timeline\.png}|{discovery-timeline.png}|' \
    -e 's|\\bibliography{\.\./references}|\\bibliography{references}|' \
    "$here/paper_ieee.tex" > "$out/main.tex"
grep -q "discovery-timeline.png}" "$out/main.tex"
cp "$here/paper_ieee.bbl" "$out/main.bbl"
cp "$paper/references.bib" "$out/references.bib"
cp "$root/docs/assets/discovery-timeline.png" "$out/discovery-timeline.png"
# Ship the fonts themselves (TeX Gyre: GUST Font License; DejaVu: Bitstream
# Vera / Arev licence, both redistributable) so arXiv's source scanner finds
# every file the preamble names; fontspec's file lookup checks the current
# directory before TeX Live.
FONTS="texgyretermes-regular.otf texgyretermes-bold.otf texgyretermes-italic.otf texgyretermes-bolditalic.otf
       DejaVuSansMono.ttf DejaVuSansMono-Bold.ttf DejaVuSansMono-Oblique.ttf DejaVuSansMono-BoldOblique.ttf"
for f in $FONTS; do
  src=$(kpsewhich "$f"); [ -n "$src" ] || { echo "font $f not in TeX Live"; exit 1; }
  cp "$src" "$out/$f"
done
cat > "$out/FONTS-README.txt" <<'TXT'
Fonts shipped with this source (both redistributable):
  texgyretermes-*.otf   TeX Gyre Termes, (c) GUST e-foundry, GUST Font License
                        (https://www.gust.org.pl/projects/e-foundry/tex-gyre)
  DejaVuSansMono*.ttf   DejaVu Sans Mono, Bitstream Vera Fonts Copyright (c) 2003
                        Bitstream, Inc.; DejaVu changes are in the public domain
                        (https://dejavu-fonts.github.io/License.html)
They are the copies from TeX Live 2025 and are included only so that the
XeLaTeX build resolves every font by file name without fontconfig.
TXT
cat > "$out/00README.json" <<'JSON'
{
  "process": { "compiler": "xelatex" },
  "sources": [ { "filename": "main.tex", "usage": "toplevel" } ]
}
JSON
# standalone test compile in a scratch copy (fresh TeX Live lookups only)
tmp=$(mktemp -d); cp "$out"/* "$tmp"/
( cd "$tmp" && xelatex -interaction=nonstopmode main.tex >log1 2>&1 || true
  xelatex -interaction=nonstopmode main.tex >log2 2>&1 || true )
# real failures only: TeX errors, unresolved cites/refs, missing glyphs, and
# a main font that failed to load (IEEEtran's ptm/sc shape warnings are benign)
if grep -qE "^! |Citation .* undefined|Reference .* undefined|Missing character|cannot be found|font .* not found" "$tmp/main.log"; then
  echo "ARXIV TEST BUILD FAILED:"; grep -nE "^! |Citation .* undefined|Reference .* undefined|Missing character|cannot be found|font .* not found" "$tmp/main.log" | head; exit 1
fi
grep -q "texgyretermes-regular" "$tmp/main.log" || { echo "main font not loaded by file name"; exit 1; }
# (kpathsea searches "." before the TeX Live font trees, so the shipped
# copies are what fontspec's file-name lookup resolves; the Latin Modern
# fonts pandoc's template loads first still come from TeX Live, as at arXiv)
pages=$(grep -oE "Output written on main.pdf \([0-9]+ pages" "$tmp/main.log" | grep -oE "[0-9]+ pages")
cp "$tmp/main.pdf" "$paper/arxiv-preview.pdf"; rm -rf "$tmp"
( cd "$out" && rm -f "$paper/foldntt-arxiv.zip" && zip -q -X "$paper/foldntt-arxiv.zip" 00README.json main.tex main.bbl references.bib discovery-timeline.png $FONTS FONTS-README.txt )
echo "arXiv package: $paper/foldntt-arxiv.zip ($pages; preview: $paper/arxiv-preview.pdf)"
unzip -l "$paper/foldntt-arxiv.zip"
