"""Step 06, line 4: DNA-level redundancy from the alignment of the assembly against itself (minimap2 PAF with base-level alignment, produced with -X so that a contig is not aligned to itself).
Usage: 06_selfalign.py SELF.paf ASSEMBLY.fasta OUT_PREFIX [MIN_BLOCK=1000]
For every base of every contig the identity of the best partner is the highest identity among the alignment blocks (of at least MIN_BLOCK aligned columns) that cover the base, taken from the blocks in which the contig is
either the query or the target. Identity of a block = matching bases / alignment columns (columns of matches, mismatches and gaps; DNA level, nucleotide identity).
Classes of the bases (as fixed in the plan): best partner at 98 % or more = false duplication (a region present twice by error); 80 % to below 95 % = real similar copy (not an error);
95 % to below 98 % = between the two; no partner of at least 80 % = no partner.
A contig is called redundant if at least 90 % of its bases have a partner at 98 % or more.
Alignments of a contig against itself (tandem and inverted repeats inside one contig) are not examined.
Writes OUT_PREFIX_classes.tsv, OUT_PREFIX_histogram.tsv (1 % bins), OUT_PREFIX_per_contig.tsv and OUT_PREFIX.json.
"""
import sys, json
import numpy as np
paf, fa, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
minblock = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
clen = {}; k = None
for l in open(fa):
    if l.startswith('>'): k = l[1:].split()[0]; clen[k] = 0
    else: clen[k] += len(l.strip())
blocks = {c: [] for c in clen}   # contig -> list of (start, end, identity)
nrec = nkept = 0
with open(paf) as f:
    for l in f:
        x = l.split('\t', 12); nrec += 1
        qn, qs, qe, tn, ts, te, mt, bl = x[0], int(x[2]), int(x[3]), x[5], int(x[7]), int(x[8]), int(x[9]), int(x[10])
        if qn == tn or bl < minblock: continue
        idt = mt / bl; nkept += 1
        blocks[qn].append((qs, qe, idt)); blocks[tn].append((ts, te, idt))
best = {}
for c, L in clen.items():
    b = np.full(L, -1.0, dtype=np.float32)
    for s, e, i in sorted(blocks[c], key=lambda t: t[2]): b[s:e] = i     # ascending identity: the highest value is written last
    best[c] = b
edges = np.arange(0, 1.0001, 0.01)
hist = np.zeros(len(edges) - 1, dtype=np.int64)
tot = 0; cls = dict(false_dup_ge98=0, between_95_and_98=0, real_similar_80_to_95=0, no_partner_ge80=0)
red = 0
with open(prefix + '_per_contig.tsv', 'w') as o:
    o.write('contig\tlength\tbases_partner_ge98\tbases_partner_95_to_98\tbases_partner_80_to_95\tbases_no_partner_ge80\tredundant_ge90pct\n')
    for c, b in best.items():
        L = len(b); tot += L
        has = b >= 0
        if has.any(): hist += np.histogram(b[has], bins=edges)[0]
        a98 = int((b >= 0.98).sum()); a95 = int(((b >= 0.95) & (b < 0.98)).sum()); a80 = int(((b >= 0.80) & (b < 0.95)).sum()); a0 = L - a98 - a95 - a80
        cls['false_dup_ge98'] += a98; cls['between_95_and_98'] += a95; cls['real_similar_80_to_95'] += a80; cls['no_partner_ge80'] += a0
        r = int(L > 0 and a98 >= 0.9 * L); red += r
        o.write(f'{c}\t{L}\t{a98}\t{a95}\t{a80}\t{a0}\t{r}\n')
with open(prefix + '_classes.tsv', 'w') as o:
    o.write('class\tbases\tfraction_of_assembly\n')
    for k, v in cls.items(): o.write(f'{k}\t{v}\t{v / tot:.6f}\n')
with open(prefix + '_histogram.tsv', 'w') as o:
    o.write('identity_from\tidentity_to\tbases\n')
    for i, h in enumerate(hist): o.write(f'{edges[i]:.2f}\t{edges[i + 1]:.2f}\t{int(h)}\n')
res = dict(assembly_bases=tot, false_duplication_bases_ge98=cls['false_dup_ge98'], false_duplication_fraction=cls['false_dup_ge98'] / tot,
           between_95_98_bases=cls['between_95_and_98'], real_similar_bases_80_to_95=cls['real_similar_80_to_95'], real_similar_fraction=cls['real_similar_80_to_95'] / tot,
           no_partner_bases=cls['no_partner_ge80'], redundant_contigs_ge90pct=red, paf_records=nrec, paf_records_used=nkept, min_block=minblock)
json.dump(res, open(prefix + '.json', 'w'), indent=1)
