#!/usr/bin/env python3
"""Convert pandoc longtables to both-column-spanning table*+tabular so they
compile under IEEEtran two-column."""
import re, sys
f = sys.argv[1]
s = open(f).read()

def conv(m):
    body = m.group(0)
    colspec = re.search(r'\\begin\{longtable\}\[\]\{([^}]*)\}', body).group(1)
    # strip longtable-only machinery
    inner = body
    inner = re.sub(r'\\begin\{longtable\}\[\]\{[^}]*\}', '', inner)
    inner = inner.replace(r'\end{longtable}', '')
    for tok in [r'\endhead', r'\endfirsthead', r'\endlastfoot', r'\endfoot']:
        inner = inner.replace(tok, '')
    inner = inner.strip()
    return ("\\begin{table*}[t]\n\\centering\\footnotesize\n"
            "\\begin{tabular}{%s}\n%s\n\\end{tabular}\n\\end{table*}" % (colspec, inner))

s2 = re.sub(r'\\begin\{longtable\}.*?\\end\{longtable\}', conv, s, flags=re.S)
open(f, 'w').write(s2)
print("converted %d longtables" % len(re.findall(r'\\begin\{table\*\}', s2)))
