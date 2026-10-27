"""Step 06, line 3: read-back of the PacBio reads on one assembly.
Usage: 06_readback.py READBACK.bam OUT_PREFIX
       [--samtools PATH] [--flank 1000] [--min-piece 500] [--end-margin 500] [--cluster-window 300] [--min-reads 3]
The BAM comes from minimap2 -ax map-pb --secondary=no, so it holds, per read, one primary record, supplementary records for the other pieces of a read that aligns in pieces, and unmapped records.

Definitions
  reads_total               reads with a primary or an unmapped record.
  aligned over >= 80 %      the aligned query intervals of all records of the read (primary and supplementary, merged) cover at least 80 % of the read length.
  one piece over >= 80 %    the primary record alone covers at least 80 % of the read length.
  identity                  1 - NM / (M + I + D) of the primary record (NM: edit distance; M, I, D: columns of the alignment); median over reads with a primary record.
  in pieces                 the read has two or more records that each align at least --min-piece query bases. Fraction of reads with an alignment.
  junction (position)       every position of a contig that is at least --flank bases from both contig ends: it is where two pieces of the assembly could have been joined wrongly.
                            A junction is spanned if one record of one read aligns across it with at least --flank aligned reference bases on each side. Positions that no read spans form
                            gaps of support (maximal runs); contigs shorter than twice --flank cannot be tested and are counted separately.
  discordant junction       two neighbouring pieces of one read (neighbours along the read) that are not collinear on the assembly: different contig, different strand, or a reference gap
                            below -1000 or above 20000 bases. Each such pair gives two break points (the ends of the two pieces that face each other). Break points within --end-margin of a contig end
                            are 'at contig ends' (a read that runs off the end of one contig into another: possible missing join); the others are 'interior' (possible wrong join, or a repeat).
                            Break points on the same contig and strand within --cluster-window bases are merged into one cluster; clusters supported by at least --min-reads different reads are reported.
"""
import sys, re, json, subprocess, argparse, collections
import numpy as np
ap = argparse.ArgumentParser(); ap.add_argument('bam'); ap.add_argument('prefix')
ap.add_argument('--samtools', default='samtools'); ap.add_argument('--flank', type=int, default=1000); ap.add_argument('--min-piece', type=int, default=500)
ap.add_argument('--end-margin', type=int, default=500); ap.add_argument('--cluster-window', type=int, default=300); ap.add_argument('--min-reads', type=int, default=3)
a = ap.parse_args()

hdr = subprocess.run([a.samtools, 'view', '-H', a.bam], capture_output=True, text=True, check=True).stdout
clen = {}
for l in hdr.splitlines():
    if l.startswith('@SQ'):
        d = dict(x.split(':', 1) for x in l.split('\t')[1:]); clen[d['SN']] = int(d['LN'])
cons = list(clen)
cov_diff = {c: np.zeros(clen[c] + 2, dtype=np.int32) for c in cons}   # difference array of trimmed (flank-spanning) coverage

def parse_cigar(c):
    b = np.frombuffer(c.encode(), dtype=np.uint8)
    isop = b > 57
    ends = np.flatnonzero(isop)
    starts = np.concatenate(([0], ends[:-1] + 1))
    digs = (b - 48).astype(np.int64)
    # number value per op: sum digit * 10^(distance from op letter)
    pos = np.arange(len(b))
    opidx = np.cumsum(isop) - isop            # index of the op each char belongs to (digits belong to the next op)
    mask = ~isop
    dist = ends[opidx[mask]] - pos[mask] - 1
    vals = np.bincount(opidx[mask], weights=digs[mask] * (10.0 ** dist), minlength=len(ends)).astype(np.int64)
    return b[ends], vals

reads = collections.defaultdict(list)   # name -> list of (qlen, qs, qe, contig, rs, re, strand, primary, ident)
n_unmapped = 0; names_total = set()
p = subprocess.Popen([a.samtools, 'view', '-@', '4', a.bam], stdout=subprocess.PIPE, text=True, bufsize=1 << 20)
tot = 0
for line in p.stdout:
    f = line.split('\t', 11)
    flag = int(f[1])
    if flag & 0x100: continue
    q = f[0]
    if flag & 4:
        n_unmapped += 1; names_total.add(q); continue
    primary = not (flag & 0x800)
    if primary: names_total.add(q)
    ops, vals = parse_cigar(f[5])
    M = vals[(ops == 77) | (ops == 61) | (ops == 88)].sum(); I = vals[ops == 73].sum(); D = vals[ops == 68].sum()
    S = vals[ops == 83].sum(); H = vals[ops == 72].sum()
    qlen = int(M + I + S + H)
    lead = int(vals[0]) if ops[0] in (83, 72) else 0
    trail = int(vals[-1]) if ops[-1] in (83, 72) else 0
    rev = bool(flag & 16)
    qs, qe = (trail, qlen - lead) if rev else (lead, qlen - trail)
    rs = int(f[3]) - 1; rlen = int(M + D); re_ = rs + rlen
    m = re.search(r'(?:^|\t)NM:i:(\d+)', f[11]) if len(f) > 11 else None
    nm = int(m.group(1)) if m else 0
    ident = 1 - nm / (M + I + D) if (M + I + D) else 0.0
    reads[q].append((qlen, qs, qe, f[2], rs, re_, '-' if rev else '+', primary, ident))
    s, e = rs + a.flank, re_ - a.flank
    if e > s:
        d = cov_diff[f[2]]; d[s] += 1; d[e] -= 1
    tot += 1
p.wait()
assert p.returncode == 0, 'samtools view failed'

n_reads = len(names_total)
n_al = ge80 = ge80_prim = pieces = 0; idents = []; qlens = []
brk = []   # (contig, strand_of_piece, position, read, at_end)
disc_pairs = 0; disc_end_pairs = 0
def merged_len(iv):
    iv = sorted(iv); tot_ = 0; cs, ce = iv[0]
    for s, e in iv[1:]:
        if s > ce: tot_ += ce - cs; cs, ce = s, e
        else: ce = max(ce, e)
    return tot_ + ce - cs
for q, recs in reads.items():
    prim = [r for r in recs if r[7]]
    if not prim: continue
    n_al += 1
    qlen = prim[0][0]; qlens.append(qlen)
    if merged_len([(r[1], r[2]) for r in recs]) >= 0.8 * qlen: ge80 += 1
    if (prim[0][2] - prim[0][1]) >= 0.8 * qlen: ge80_prim += 1
    idents.append(prim[0][8])
    big = sorted([r for r in recs if r[2] - r[1] >= a.min_piece], key=lambda r: r[1])
    if len(big) >= 2:
        pieces += 1
        for r1, r2 in zip(big[:-1], big[1:]):
            same = r1[3] == r2[3] and r1[6] == r2[6]
            if same:
                gap = (r2[4] - r1[5]) if r1[6] == '+' else (r1[4] - r2[5])
                if -1000 <= gap <= 20000: continue
            disc_pairs += 1
            for r, side in ((r1, 'out'), (r2, 'in')):
                # reference end of the piece that faces the junction
                if (r[6] == '+') == (side == 'out'): pos = r[5]
                else: pos = r[4]
                L = clen[r[3]]
                at_end = pos < a.end_margin or pos > L - a.end_margin
                brk.append((r[3], pos, q, at_end))
# clusters of break points
clusters = []
by = collections.defaultdict(list)
for c, pos, q, at_end in brk: by[(c, at_end)].append((pos, q))
for (c, at_end), v in by.items():
    v.sort(); cur = [v[0]]
    for x in v[1:]:
        if x[0] - cur[-1][0] <= a.cluster_window: cur.append(x)
        else:
            clusters.append((c, at_end, cur)); cur = [x]
    clusters.append((c, at_end, cur))
with open(a.prefix + '_discordant_junctions.tsv', 'w') as o:
    o.write('contig\tposition_start\tposition_end\tlocation\treads\n')
    nint = nend = 0
    for c, at_end, cur in sorted(clusters, key=lambda t: (t[0], t[2][0][0])):
        nr = len({q for _, q in cur})
        if nr >= a.min_reads:
            o.write(f'{c}\t{cur[0][0]}\t{cur[-1][0]}\t{"contig_end" if at_end else "interior"}\t{nr}\n')
            nint += (not at_end); nend += at_end

# unspanned junction positions
gaps = []; tested_bases = unspanned_bases = n_short = 0
with open(a.prefix + '_per_contig.tsv', 'w') as o:
    o.write('contig\tlength\ttested_bases\tunspanned_bases\tunspanned_gaps\n')
    for c in cons:
        L = clen[c]
        if L < 2 * a.flank + 1:
            n_short += 1; o.write(f'{c}\t{L}\t0\t0\t0\n'); continue
        cov = np.cumsum(cov_diff[c][:L])
        reg = cov[a.flank:L - a.flank]
        z = np.concatenate(([0], (reg == 0).astype(np.int8), [0])); dz = np.diff(z)
        st = np.flatnonzero(dz == 1); en = np.flatnonzero(dz == -1)
        for s, e in zip(st, en): gaps.append((c, int(s) + a.flank, int(e) + a.flank))
        ub = int((reg == 0).sum()); tested_bases += len(reg); unspanned_bases += ub
        o.write(f'{c}\t{L}\t{len(reg)}\t{ub}\t{len(st)}\n')
with open(a.prefix + '_unspanned_gaps.tsv', 'w') as o:
    o.write('contig\tstart_0based\tend\tlength\n')
    for c, s, e in gaps: o.write(f'{c}\t{s}\t{e}\t{e - s}\n')

res = dict(
    reads_total=n_reads, reads_unmapped=n_unmapped, reads_with_alignment=n_al,
    frac_reads_aligned_ge80pct=ge80 / n_reads if n_reads else None,
    frac_reads_one_piece_ge80pct=ge80_prim / n_reads if n_reads else None,
    median_identity=float(np.median(idents)) if idents else None,
    reads_in_pieces=pieces, frac_reads_in_pieces=pieces / n_al if n_al else None,
    discordant_junction_pairs=disc_pairs,
    discordant_junction_clusters_interior_ge_min_reads=nint, discordant_junction_clusters_at_contig_ends_ge_min_reads=nend,
    junction_test_contigs_too_short=n_short, junction_tested_bases=tested_bases,
    unspanned_bases=unspanned_bases, unspanned_gaps=len(gaps),
    frac_tested_bases_unspanned=unspanned_bases / tested_bases if tested_bases else None,
    parameters=dict(flank=a.flank, min_piece=a.min_piece, end_margin=a.end_margin, cluster_window=a.cluster_window, min_reads=a.min_reads))
json.dump(res, open(a.prefix + '.json', 'w'), indent=1)
