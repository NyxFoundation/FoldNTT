#!/usr/bin/env python3
"""Convert pandoc longtables to both-column-spanning table*+tabular so they
compile under IEEEtran two-column."""
import re, sys
f = sys.argv[1]
s = open(f).read()

def conv(m):
    body = m.group(0)
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
    return ("\\begin{table*}[t]\n\\centering\\footnotesize\n"
            "\\begin{tabular}{%s}\n%s\n\\end{tabular}\n\\end{table*}" % (colspec, inner))

s2 = re.sub(r'\\begin\{longtable\}.*?\\end\{longtable\}', conv, s, flags=re.S)
open(f, 'w').write(s2)
print("converted %d longtables" % len(re.findall(r'\\begin\{table\*\}', s2)))
