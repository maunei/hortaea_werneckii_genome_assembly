"""Step 06, line 3 (descriptive): telomeric repeats at the ends of the contigs.
Usage: 06_telomeres.py ASSEMBLY.fasta OUT_PREFIX [WINDOW=400] [MIN_REPEATS=6]
An end carries a telomere repeat if the first (left end) or the last (right end) WINDOW bases contain MIN_REPEATS or more uninterrupted copies of TTAGGG (on the top strand) or of its reverse complement CCCTAA (the same repeat read on the other strand).
Writes OUT_PREFIX.tsv (one row per contig) and OUT_PREFIX.json (contigs with repeats at both ends, at one end, at none).
Contigs shorter than twice WINDOW have overlapping windows; they are counted with the others and listed in the key contigs_shorter_than_two_windows.
"""
import sys, re, json
fa, prefix = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 400
K = int(sys.argv[4]) if len(sys.argv) > 4 else 6
fw = re.compile('(?:TTAGGG){%d,}' % K); rc = re.compile('(?:CCCTAA){%d,}' % K)
def reads(path):
    name, parts = None, []
    for line in open(path):
        if line.startswith('>'):
            if name is not None: yield name, ''.join(parts).upper()
            name, parts = line[1:].split()[0], []
        else: parts.append(line.strip())
    if name is not None: yield name, ''.join(parts).upper()
def end_call(win):
    f, r = fw.search(win), rc.search(win)
    if f and r: return 'both_strands'
    return 'TTAGGG' if f else ('CCCTAA' if r else 'none')
n = both = one = none = short = 0
with open(prefix + '.tsv', 'w') as o:
    o.write('contig\tlength\tleft_end\tright_end\tends_with_repeat\n')
    for name, s in reads(fa):
        l, r = end_call(s[:W]), end_call(s[-W:]); k = (l != 'none') + (r != 'none')
        n += 1; both += k == 2; one += k == 1; none += k == 0; short += len(s) < 2 * W
        o.write(f'{name}\t{len(s)}\t{l}\t{r}\t{k}\n')
res = dict(contigs=n, with_repeat_at_both_ends=both, with_repeat_at_one_end=one, with_no_repeat=none, contigs_shorter_than_two_windows=short, window_bases=W, min_repeats=K)
json.dump(res, open(prefix + '.json', 'w'), indent=1)
