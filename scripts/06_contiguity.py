"""Step 06, line 1: contiguity of one assembly.
Usage: 06_contiguity.py ASSEMBLY.fasta GENOME_SIZE OUT_PREFIX
Writes OUT_PREFIX.tsv (one row per contig set: all contigs, contigs of at least 10 kb) and OUT_PREFIX.json.
Definitions (lengths sorted from the longest):
  N50  length of the contig at which the running sum first reaches half of the total length of the set;  L50 number of contigs up to and including it.
  NG50 / LG50  the same, with half of GENOME_SIZE in place of half of the total length (0 if the set is shorter than half of GENOME_SIZE).
  auN  area under the Nx curve = sum(length^2) / sum(length).
  gc_percent  100 * (G + C) / (A + C + G + T), upper and lower case, ambiguous bases left out.
"""
import sys, json
import numpy as np

fa, genome_size, prefix = sys.argv[1], int(sys.argv[2]), sys.argv[3]
names, lens, gc, acgt, nn = [], [], [], [], []
cur = None
def close():
    if cur is not None:
        s = b''.join(cur).upper()
        c = {k: s.count(k) for k in (b'A', b'C', b'G', b'T', b'N')}
        lens.append(len(s)); gc.append(c[b'G'] + c[b'C']); acgt.append(c[b'A'] + c[b'C'] + c[b'G'] + c[b'T']); nn.append(len(s) - c[b'A'] - c[b'C'] - c[b'G'] - c[b'T'])
with open(fa, 'rb') as f:
    for line in f:
        if line.startswith(b'>'):
            close(); cur = []; names.append(line[1:].split()[0].decode())
        else:
            cur.append(line.strip())
close()
L = np.array(lens, dtype=np.int64); GC = np.array(gc); AC = np.array(acgt); NN = np.array(nn)
assert len(L) > 0, 'no sequences in ' + fa
assert len(set(names)) == len(names), 'contig names are not unique'

def stats(mask):
    l = np.sort(L[mask])[::-1]
    if len(l) == 0:
        return dict(contigs=0, total_bp=0, n50=0, l50=0, ng50=0, lg50=0, aun=0.0, longest=0, gc_percent=None, ambiguous_bases=0)
    cs = np.cumsum(l); tot = int(cs[-1])
    i50 = int(np.searchsorted(cs, tot / 2)); 
    if cs[-1] >= genome_size / 2:
        ig = int(np.searchsorted(cs, genome_size / 2)); ng50, lg50 = int(l[ig]), ig + 1
    else:
        ng50, lg50 = 0, 0
    a = int(AC[mask].sum())
    return dict(contigs=int(len(l)), total_bp=tot, n50=int(l[i50]), l50=i50 + 1, ng50=ng50, lg50=lg50, aun=float((l.astype(float) ** 2).sum() / tot),
                longest=int(l[0]), gc_percent=float(100 * GC[mask].sum() / a) if a else None, ambiguous_bases=int(NN[mask].sum()))
res = {'all': stats(np.ones(len(L), bool)), 'ge10kb': stats(L >= 10000), 'genome_size_used_for_ng50': genome_size}
keys = ['contigs', 'total_bp', 'n50', 'l50', 'ng50', 'lg50', 'aun', 'longest', 'gc_percent', 'ambiguous_bases']
with open(prefix + '.tsv', 'w') as o:
    o.write('contig_set\t' + '\t'.join(keys) + '\n')
    for s in ('all', 'ge10kb'):
        o.write(s + '\t' + '\t'.join('NA' if res[s][k] is None else (f'{res[s][k]:.4f}' if isinstance(res[s][k], float) else str(res[s][k])) for k in keys) + '\n')
json.dump(res, open(prefix + '.json', 'w'), indent=1)
