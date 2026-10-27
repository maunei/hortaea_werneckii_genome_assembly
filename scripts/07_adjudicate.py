"""Decides each disagreement between assemblies A and B with the PacBio reads.
Inputs: the table of disagreements (07_find_disagreements.py), the compact read alignments to A and to B (07_compact_read_alignments.py), the two FASTA files (for contig lengths).
For every disagreement the two arrangements are tested separately, each in the alignment of the reads to the assembly that holds it:
  - Windows: the junction points of an arrangement on its assembly, each widened by FLANK bases on both sides (points closer than 2 x FLANK are merged into one window).
    Windows that would reach outside the contig are dropped.
  - A read supports an arrangement when one alignment record of the read (mapping quality >= MIN_MAPQ) covers a whole window and has no insertion or deletion of
    GAP_MIN bases or more inside it. Each read is counted once per arrangement.
  - For a join (one assembly is continuous where the other is broken) the broken assembly has no window that a read could cross; the reads for it are the reads
    that are aligned up to the junction of the continuous assembly (within TOL bases, at least FLANK bases aligned next to it) and carry at least OVERHANG further bases that do not continue there ('clipped reads').
  - A read that crosses a window of both arrangements (for example inside a duplicated sequence) does not discriminate and is counted as 'neither'.
  - 'neither': reads that overlap a window or a junction by at least 100 bases but support neither arrangement.
Decision: decided if reads that span number at least MIN_READS (3) for one arrangement and at least twice those of the other; 'mixed' if at least MIN_READS reads
span in total but this is not met; 'insufficient' otherwise.
Usage: 07_adjudicate.py DISAGREEMENTS.tsv READS_TO_A.tsv.gz READS_TO_B.tsv.gz A.fa B.fa A_LABEL B_LABEL OUT_DIR"""
import sys, gzip, json, math, bisect, collections, os
dis, ra, rb, fa_a, fa_b, la, lb, outdir = sys.argv[1:9]
FLANK = int(os.environ.get('FLANK', 500)); MIN_MAPQ = int(os.environ.get('MIN_MAPQ', 10)); GAP_MIN = int(os.environ.get('GAP_MIN', 200))
MIN_READS = int(os.environ.get('MIN_READS', 3)); TOL = int(os.environ.get('TOL', 300)); OVERHANG = int(os.environ.get('OVERHANG', 500))
def lengths(fa):
    L, k = {}, None
    for line in open(fa):
        if line.startswith('>'): k = line[1:].split()[0]; L[k] = 0
        else: L[k] += len(line.strip())
    return L
LEN = {'A': lengths(fa_a), 'B': lengths(fa_b)}
def load(path):
    rows = collections.defaultdict(list)
    with gzip.open(path, 'rt') as fh:
        next(fh)
        for line in fh:
            r, qlen, qs, qe, st, c, tlen, ts, te, mq, gp = line.rstrip('\n').split('\t')
            gaps = [] if gp == '.' else [(g.split(':')[0], int(g.split(':')[1]), int(g.split(':')[2])) for g in gp.split(',')]
            rows[c].append((int(ts), int(te), r, int(mq), int(qs), int(qe), int(qlen), st, gaps))
    idx = {}
    for c, v in rows.items():
        v.sort(); idx[c] = (v, [x[0] for x in v], max(x[1] - x[0] for x in v))
    return idx
ALN = {'A': load(ra), 'B': load(rb)}
def overlapping(asm, c, start, end):
    """alignment records of the reads on contig c overlapping [start, end)"""
    if c not in ALN[asm]: return
    v, ts, mx = ALN[asm][c]
    i = bisect.bisect_left(ts, end)
    j = i - 1
    while j >= 0 and ts[j] >= start - mx:
        if v[j][1] > start: yield v[j]
        j -= 1
def gap_in(rec, start, end):
    for typ, pos, n in rec[8]:
        a, b = (pos, pos + n) if typ == 'D' else (pos, pos)
        if a < end and b > start: return True
    return False
def windows(asm, pts):
    byc = collections.defaultdict(list)
    for c, p in pts: byc[c].append(p)
    out = []
    for c, ps in byc.items():
        ps.sort(); cur = [ps[0], ps[0]]
        for p in ps[1:]:
            if p - cur[1] < 2 * FLANK: cur[1] = p
            else: out.append((c, cur[0] - FLANK, cur[1] + FLANK)); cur = [p, p]
        out.append((c, cur[0] - FLANK, cur[1] + FLANK))
    return [w for w in out if w[1] >= 0 and w[2] <= LEN[asm].get(w[0], 0)]
def spanning(asm, wins):
    s, ov = set(), set()
    for c, a, b in wins:
        for rec in overlapping(asm, c, a, b):
            if rec[3] < MIN_MAPQ: continue
            if min(rec[1], b) - max(rec[0], a) >= 100: ov.add(rec[2])
            if rec[0] <= a and rec[1] >= b and not gap_in(rec, a, b): s.add(rec[2])
    return s, ov
def clipped(asm, c, f1, f2):
    """reads aligned up to the junction (points f1 and f2 on contig c) that continue with sequence that does not align there"""
    out = set()
    for rec in overlapping(asm, c, f1 - FLANK - TOL, f1 + TOL + 1):
        ts, te, r, mq, qs, qe, qlen, st, g = rec
        if mq < MIN_MAPQ: continue
        if abs(te - f1) <= TOL and ts <= f1 - FLANK and (qlen - qe if st == '+' else qs) >= OVERHANG: out.add(r)
    for rec in overlapping(asm, c, f2 - TOL, f2 + FLANK + TOL + 1):
        ts, te, r, mq, qs, qe, qlen, st, g = rec
        if mq < MIN_MAPQ: continue
        if abs(ts - f2) <= TOL and te >= f2 + FLANK and (qs if st == '+' else qlen - qe) >= OVERHANG: out.add(r)
    return out
def wilson(k, n, z=1.959964):
    if n == 0: return (None, None)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))
rows = []
with open(dis) as fh:
    head = next(fh).rstrip('\n').split('\t')
    for line in fh: rows.append(dict(zip(head, line.rstrip('\n').split('\t'))))
res = []
for r in rows:
    typ, focus = r['type'], r['focus']; other = 'B' if focus == 'A' else 'A'
    fpts = [(r['focus_contig'], int(p)) for p in r['focus_points'].split(',')]
    opts = [(x.rsplit(':', 1)[0], int(x.rsplit(':', 1)[1])) for x in r['other_points'].split(',')]
    wf = windows(focus, fpts)
    sf, ovf = spanning(focus, wf)
    if typ.startswith('join_in_'):
        # the junction of the focus assembly: first and last point
        so = clipped(focus, r['focus_contig'], fpts[0][1], fpts[-1][1]); wo = []; ovo = set(); method = 'span_and_clipped_reads'
    else:
        wo = windows(other, opts); so, ovo = spanning(other, wo); method = 'span'
    both = sf & so                       # reads that cross a window of both arrangements (for example the repeated sequence of a duplication) do not discriminate
    sf, so = sf - both, so - both
    neither = (ovf | ovo | both) - sf - so
    nF, nO = len(sf), len(so)
    nA, nB = (nF, nO) if focus == 'A' else (nO, nF)
    if nA >= MIN_READS and nA >= 2 * nB: status = 'decided_A'
    elif nB >= MIN_READS and nB >= 2 * nA: status = 'decided_B'
    elif nA + nB >= MIN_READS: status = 'mixed'
    else: status = 'insufficient'
    wA, wB = (wf, wo) if focus == 'A' else (wo, wf)
    r.update(reads_A=nA, reads_B=nB, reads_neither=len(neither), status=status, method=method,
             windows_A=';'.join('%s:%d-%d' % w for w in wA) or '.', windows_B=';'.join('%s:%d-%d' % w for w in wB) or '.')
    res.append(r)
os.makedirs(outdir, exist_ok=True)
cols = head + ['reads_A', 'reads_B', 'reads_neither', 'status', 'method', 'windows_A', 'windows_B']
with open(os.path.join(outdir, 'disagreements.tsv'), 'w') as out:
    out.write('\t'.join(cols) + '\n')
    for r in res: out.write('\t'.join(str(r[c]) for c in cols) + '\n')
n = len(res); cnt = collections.Counter(r['status'] for r in res)
bytype = collections.defaultdict(lambda: collections.Counter())
for r in res: bytype[r['type']][r['status']] += 1
def prop(k):
    lo, hi = wilson(k, n)
    return dict(count=k, proportion=(k / n if n else None), ci95_low=lo, ci95_high=hi)
dec = cnt['decided_A'] + cnt['decided_B']
lo, hi = wilson(cnt['decided_A'], dec)
summary = dict(A=la, B=lb, disagreements=n,
               by_type={t: dict(total=sum(c.values()), **dict(c)) for t, c in sorted(bytype.items())},
               decided_for_A=prop(cnt['decided_A']), decided_for_B=prop(cnt['decided_B']),
               undecided=prop(cnt['mixed'] + cnt['insufficient']), undecided_mixed=cnt['mixed'], undecided_insufficient=cnt['insufficient'],
               fraction_of_decided_for_A=dict(count=cnt['decided_A'], of=dec, proportion=(cnt['decided_A'] / dec if dec else None), ci95_low=lo, ci95_high=hi),
               interval_method='Wilson score interval, 95 percent, with the number of disagreements (or of decided disagreements) as the sample size',
               settings=dict(flank=FLANK, min_mapq=MIN_MAPQ, gap_min=GAP_MIN, min_reads=MIN_READS, tolerance_clipped=TOL, overhang_clipped=OVERHANG))
json.dump(summary, open(os.path.join(outdir, 'summary.json'), 'w'), indent=1)
print(json.dumps(summary)[:1500])
