#!/usr/bin/env python3
"""Convert pandoc longtables to both-column-spanning table*+tabular so they
compile under IEEEtran two-column.  A bold "Table N. ..." paragraph
immediately before a longtable (the caption convention in paper.md) is
absorbed into a real \\caption{} inside the float, so tables carry their
number and title; numbering is sequential, matching the manual numbers."""
import re, sys
f = sys.argv[1]
s = open(f).read()

def conv(m):
    caption = m.group('cap')
    body = m.group('tbl')
    colspec = re.search(r'\\begin\{longtable\}\[\]\{([^}]*)\}', body).group(1)
    inner = body
    inner = re.sub(r'\\begin\{longtable\}\[\]\{[^}]*\}', '', inner)
    inner = inner.replace(r'\end{longtable}', '')

    # pandoc longtable anatomy, in file order:
    #   firsthead \endfirsthead  head \endhead  [foot \endfoot]
    #   lastfoot (\bottomrule) \endlastfoot  BODY
    # Rebuild as head + BODY + lastfoot, so the bottom rule lands at the
    # bottom instead of between the header and the body.
    def take(tok, s):
        mm = re.search(r'(.*?)\\' + tok, s, re.S)
        return (mm.group(1).strip(), s[mm.end():]) if mm else ('', s)

    firsthead, rest = take('endfirsthead', inner)
    head, rest = take('endhead', rest)
    foot, rest = take('endfoot', rest)
    lastfoot, rest = take('endlastfoot', rest)
    parts = [head or firsthead, rest.strip(), lastfoot or foot]
    inner = '\n'.join(p for p in parts if p)
    cap = ''
    if caption:
        cap = "\\caption{%s}\n" % ' '.join(caption.split())
    # table notes (paragraphs starting with * / dagger / ddagger right after the
    # table in paper.md) travel inside the float, under the tabular
    notes = (m.group('notes') or '').strip()
    notes_tex = ''
    if notes:
        paras = [' '.join(x.split()) for x in re.split(r'\n\s*\n', notes) if x.strip()]
        notes_tex = ("\n\\par\\vspace{3pt}\\begin{minipage}{\\linewidth}\\scriptsize\n"
                     + "\\par ".join(paras) + "\n\\end{minipage}")
    global tblno
    tblno += 1
    if tblno in SINGLE_COL:
        # narrow enough for one 3.5in column: a single-column float can sit
        # on the same page as (or right after) its reference
        return ("\\begin{table}[!t]\n\\centering\\scriptsize\n%s"
                "\\begin{tabular}{%s}\n%s\n\\end{tabular}%s\n\\end{table}"
                % (cap, colspec, inner, notes_tex))
    return ("\\begin{table*}[!t]\n\\centering\\footnotesize\n%s"
            "\\begin{tabular}{%s}\n%s\n\\end{tabular}%s\n\\end{table*}"
            % (cap, colspec, inner, notes_tex))

# tables (in order of appearance) whose natural width fits one column;
# the rest must span both columns
SINGLE_COL = {2}
tblno = 0

pat = re.compile(
    r'(?:\\textbf\{Table\s+[0-9]+\.\s+(?P<cap>(?:[^{}]|\{[^{}]*\})*?)\}\s*\n\s*\n)?'
    r'(?P<tbl>\\begin\{longtable\}.*?\\end\{longtable\})'
    r'(?P<notes>(?:\s*\n\s*\n(?:\*|\\dag|\\ddag|†|‡)[^\n]*(?:\n(?!\s*\n)[^\n]*)*)*)', re.S)
s2 = pat.sub(conv, s)
open(f, 'w').write(s2)
ncap = len(re.findall(r'\\caption\{', s2)) - s.count('\\caption{')
print("converted %d longtables (%d with captions)"
      % (len(re.findall(r'\\begin\{table\*\}', s2)), ncap))
