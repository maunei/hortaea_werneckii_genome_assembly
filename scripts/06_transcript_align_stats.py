"""Scores the alignment of de novo transcripts to one assembly.
Input: PAF file of minimap2 (with the cigar and the NM tag, primary and supplementary alignments only) and the transcript FASTA.
For every transcript the alignment pieces are combined as follows.
  - aligned length = number of transcript bases covered by at least one piece (union of the intervals on the transcript)
  - coverage = aligned length / transcript length
  - identity = 1 - (mismatches + inserted + deleted bases) / (aligned columns), pooled over the pieces; introns (N in the cigar) are not counted
  - 'on one contig' = the same two measures computed from the pieces on the single contig that gives the highest coverage
A transcript passes when coverage >= MIN_COV (0.90) and identity >= MIN_ID (0.95).
Usage: 06_transcript_align_stats.py TRANSCRIPTS.fa ALIGNMENTS.paf OUT_PREFIX ASM_NAME   (writes OUT_PREFIX.transcripts.tsv.gz and OUT_PREFIX.summary.json)"""
import sys, re, json, gzip, collections
MIN_COV, MIN_ID = 0.90, 0.95
fa, paf, prefix, asm = sys.argv[1:5]
qlen, order = {}, []
with open(fa) as fh:
    k = None
    for line in fh:
        if line.startswith('>'):
            k = line[1:].split()[0]; qlen[k] = 0; order.append(k)
        else:
            qlen[k] += len(line.strip())
cig = re.compile(r'(\d+)([MIDNSHP=X])')
pieces = collections.defaultdict(list)       # transcript -> list of (qs, qe, target, columns, nm, introns)
for line in open(paf):
    f = line.rstrip('\n').split('\t')
    tags = {t[:2]: t[5:] for t in f[12:]}
    if tags.get('tp') == 'S': continue           # secondary alignment (not requested, kept as a safeguard)
    cols = nm_cigar = introns = 0
    for n, op in cig.findall(tags.get('cg', '')):
        n = int(n)
        if op in 'M=X': cols += n
        elif op in 'ID': cols += n
        elif op == 'N': introns += 1
    nm = int(tags['NM']) if 'NM' in tags else None
    if nm is None:
        raise SystemExit('NM tag missing: run minimap2 with -c')
    pieces[f[0]].append((int(f[2]), int(f[3]), f[5], cols, nm, introns))
def union(iv):
    iv = sorted(iv); tot = 0; cs, ce = iv[0]
    for s, e in iv[1:]:
        if s <= ce: ce = max(ce, e)
        else: tot += ce - cs; cs, ce = s, e
    return tot + ce - cs
rows = []
for q in order:
    L = qlen[q]; p = pieces.get(q)
    if not p:
        rows.append((q, L, 0, 0.0, 0.0, '', 0.0, 0.0, 0, 0)); continue
    cov = union([(a, b) for a, b, *_ in p]) / L
    cols = sum(x[3] for x in p); nm = sum(x[4] for x in p)
    ident = 1 - nm / cols if cols else 0.0
    bytarget = collections.defaultdict(list)
    for x in p: bytarget[x[2]].append(x)
    best = max(bytarget.items(), key=lambda kv: union([(a, b) for a, b, *_ in kv[1]]))
    c1 = union([(a, b) for a, b, *_ in best[1]]) / L
    cols1 = sum(x[3] for x in best[1]); nm1 = sum(x[4] for x in best[1])
    id1 = 1 - nm1 / cols1 if cols1 else 0.0
    rows.append((q, L, len(p), cov, ident, best[0], c1, id1, sum(x[5] for x in p), len(bytarget)))
with gzip.open(prefix + '.transcripts.tsv.gz', 'wt') as out:
    out.write('transcript\tlength\tpieces\tcoverage\tidentity\tbest_contig\tcoverage_best_contig\tidentity_best_contig\tintrons\tcontigs_hit\n')
    for r in rows:
        out.write('\t'.join(str(x) if not isinstance(x, float) else '%.4f' % x for x in r) + '\n')
n = len(rows)
aligned = sum(1 for r in rows if r[2] > 0)
cov50 = sum(1 for r in rows if r[3] >= 0.5)
cov90 = sum(1 for r in rows if r[3] >= MIN_COV)
passed = sum(1 for r in rows if r[3] >= MIN_COV and r[4] >= MIN_ID)
passed1 = sum(1 for r in rows if r[6] >= MIN_COV and r[7] >= MIN_ID)
spliced = sum(1 for r in rows if r[3] >= MIN_COV and r[4] >= MIN_ID and r[8] > 0)
# gene level: Trinity names isoforms TRINITY_DNxxx_cX_gY_iZ; a gene passes when its longest isoform passes
gene = {}
for r in rows:
    g = re.sub(r'_i\d+$', '', r[0])
    if g not in gene or r[1] > gene[g][1]: gene[g] = r
genes_pass = sum(1 for r in gene.values() if r[3] >= MIN_COV and r[4] >= MIN_ID)
res = dict(assembly=asm, transcripts=n, aligned=aligned, frac_aligned=aligned / n if n else None,
           aligned_ge50pct=cov50, frac_aligned_ge50pct=cov50 / n if n else None,
           aligned_ge90pct_any_identity=cov90, frac_aligned_ge90pct_any_identity=cov90 / n if n else None,
           pass_ge90pct_ge95id=passed, frac_pass_ge90pct_ge95id=passed / n if n else None,
           pass_on_one_contig=passed1, frac_pass_on_one_contig=passed1 / n if n else None,
           pass_with_intron=spliced, genes=len(gene), genes_pass_longest_isoform=genes_pass,
           frac_genes_pass_longest_isoform=genes_pass / len(gene) if gene else None,
           min_coverage=MIN_COV, min_identity=MIN_ID)
json.dump(res, open(prefix + '.summary.json', 'w'), indent=1)
print(json.dumps(res))
