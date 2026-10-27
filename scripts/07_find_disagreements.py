"""Lists the structural disagreements between two assemblies A and B from the alignment of A (query) to B (target) made by minimap2 (PAF with cigar).

Definitions (all lengths in bases; the settings are the command-line options, defaults in brackets)
  piece        an aligned stretch of one contig of A on one contig of B in one orientation. A PAF record is cut at every insertion or deletion of
               at least MIN_SV bases (1000) in its cigar; pieces shorter than MIN_PIECE (5000) on A are dropped; a piece that is covered to more than
               half of its length by longer pieces on the same contig of A is dropped (it is a second copy, not a different arrangement).
  junction     two pieces that follow each other along one contig of A (focus A) or along one contig of B (focus B; pieces are swapped).
               Taking both views finds the arrangements in which A is continuous where B is broken and those in which B is continuous where A is broken.
  types, for a junction between pieces p1 and p2 (focus F is A or B, the other assembly is O):
    insertion_in_F        same contig and orientation in O, p2 follows p1 there, and F holds at least MIN_SV more bases between the pieces than O does
    deletion_in_F         the same, with O holding at least MIN_SV more bases (F lacks them)
    duplication_in_F      same contig and orientation, p2 starts in O behind the end of p1 by more than MIN_SV but not more than the shorter piece (F repeats a segment that O holds once)
    inversion_in_F        three pieces p1, p2, p3 on the same contig of O with p2 in the opposite orientation to p1 and p3 and its far end within MAX_LOCAL of the end of p1
    inversion_breakpoint_in_F   one such strand change not closed by a third piece
    relocation_in_F       same contig of O, but p2 is not where p1 leads to (other order, distant, or strand change that is not local)
    join_in_F             p1 and p2 lie on different contigs of O and each ends within END_TOL (10000) of the contig end of O that it points to: F is continuous where O is broken (a break in O)
    translocation_in_F    p1 and p2 lie on different contigs of O that both continue past the junction
Output: TSV with one row per disagreement. Columns: id, type, focus, F_contig, F_point1, F_point2 (the junction on the focus contig), O_contig1, O_point1, O_contig2, O_point2
(the matching points on the other assembly; for a join these are contig ends), size (bases of difference: |indel|, duplicated or inverted length, else 0), pieces.
Usage: 07_find_disagreements.py ALN.paf A_LABEL B_LABEL OUT.tsv [--min-sv N] [--min-piece N] [--end-tol N] [--max-local N]"""
import sys, re, argparse, collections
ap = argparse.ArgumentParser()
ap.add_argument('paf'); ap.add_argument('a'); ap.add_argument('b'); ap.add_argument('out')
ap.add_argument('--min-sv', type=int, default=1000); ap.add_argument('--min-piece', type=int, default=5000)
ap.add_argument('--end-tol', type=int, default=10000); ap.add_argument('--max-local', type=int, default=20000)
ap.add_argument('--stats', default=None, help='optional JSON file for alignment statistics')
o = ap.parse_args()
cig = re.compile(r'(\d+)([MIDNSHP=X])')
raw = []     # pieces as dicts: qn, qlen, qa, qb, st, tn, tlen, ta, tb
for line in open(o.paf):
    f = line.rstrip('\n').split('\t')
    tags = {t[:2]: t[5:] for t in f[12:]}
    if tags.get('tp') == 'S': continue
    if 'cg' not in tags: raise SystemExit('cigar missing: run minimap2 with -c')
    qn, qlen, qs, qe, st, tn, tlen, ts, te = f[0], int(f[1]), int(f[2]), int(f[3]), f[4], f[5], int(f[6]), int(f[7]), int(f[8])
    qpos = qs if st == '+' else qe       # position on A where the cigar starts (for '-' the cigar runs against the forward strand of A)
    tpos = ts
    seg_q0, seg_t0 = qpos, tpos
    def close(q1, t1):
        global seg_q0, seg_t0
        qa, qb = sorted((seg_q0, q1)); ta, tb = sorted((seg_t0, t1))
        if qb - qa > 0 and tb - ta > 0: raw.append(dict(qn=qn, qlen=qlen, qa=qa, qb=qb, st=st, tn=tn, tlen=tlen, ta=ta, tb=tb))
    for n, op in cig.findall(tags['cg']):
        n = int(n)
        if op in 'M=X':
            qpos += n if st == '+' else -n; tpos += n
        elif op == 'I':
            if n >= o.min_sv:
                close(qpos, tpos); qpos += n if st == '+' else -n; seg_q0, seg_t0 = qpos, tpos
            else: qpos += n if st == '+' else -n
        elif op == 'D':
            if n >= o.min_sv:
                close(qpos, tpos); tpos += n; seg_q0, seg_t0 = qpos, tpos
            else: tpos += n
        elif op == 'N': tpos += n
    close(qpos, tpos)
raw = [p for p in raw if p['qb'] - p['qa'] >= o.min_piece]
# drop pieces mostly covered by longer pieces on the same contig of A
raw.sort(key=lambda p: -(p['qb'] - p['qa']))
acc = collections.defaultdict(list); pieces = []
for p in raw:
    cov = 0
    for q in acc[p['qn']]:
        cov += max(0, min(p['qb'], q['qb']) - max(p['qa'], q['qa']))
    if cov > 0.5 * (p['qb'] - p['qa']): continue
    acc[p['qn']].append(p); pieces.append(p)
for i, p in enumerate(pieces): p['id'] = i
def swapped(p):
    return dict(id=p['id'], qn=p['tn'], qlen=p['tlen'], qa=p['ta'], qb=p['tb'], st=p['st'], tn=p['qn'], tlen=p['qlen'], ta=p['qa'], tb=p['qb'])
events, seen = [], set()
def junctions(plist, focus):
    """plist: pieces with the focus assembly as query. Returns events for this focus."""
    byc = collections.defaultdict(list)
    for p in plist: byc[p['qn']].append(p)
    out = []
    for qn, ps in byc.items():
        ps.sort(key=lambda p: p['qa'])
        js = []
        for p1, p2 in zip(ps, ps[1:]):
            s1, s2 = p1['st'], p2['st']
            e1 = p1['tb'] if s1 == '+' else p1['ta']             # point on the other assembly where p1 leads to
            b2 = p2['ta'] if s2 == '+' else p2['tb']             # point where p2 starts
            d1 = 1 if s1 == '+' else -1
            gq = p2['qa'] - p1['qb']
            typ, size, b2use = None, 0, b2
            if p1['tn'] == p2['tn']:
                if s1 == s2:
                    gt = (b2 - e1) * d1
                    d = gt - gq
                    if gt < -o.min_sv:
                        ov = -gt
                        typ = 'duplication' if ov <= min(p1['qb'] - p1['qa'], p2['qb'] - p2['qa']) else 'relocation'; size = ov
                    elif d >= o.min_sv: typ, size = 'deletion', d
                    elif d <= -o.min_sv: typ, size = 'insertion', -d
                else:
                    # An inversion changes the orientation of one piece. In the other assembly the sequence continues from p1 into the far end of p2
                    # (the first breakpoint of an inversion, p2 inverted) or from the far end of p1 into p2 (the second breakpoint, p1 inverted).
                    o2 = p2['ta'] if s2 == '-' else p2['tb']       # far end of p2 as seen from p1
                    o1 = p1['tb'] if s1 == '-' else p1['ta']       # far end of p1 as seen from p2
                    d_flip2, d_flip1 = abs(o2 - e1), abs(b2 - o1)
                    if min(d_flip2, d_flip1) <= o.max_local:
                        typ = 'inversion_breakpoint'
                        if d_flip2 <= d_flip1: b2use, size = o2, abs(p2['tb'] - p2['ta'])
                        else: e1, b2use, size = o1, b2, abs(p1['tb'] - p1['ta'])
                    else: typ = 'relocation'
            else:
                end1 = (p1['tlen'] - p1['tb']) if s1 == '+' else p1['ta']
                end2 = p2['ta'] if s2 == '+' else (p2['tlen'] - p2['tb'])
                typ = 'join' if (end1 <= o.end_tol and end2 <= o.end_tol) else 'translocation'
            js.append(dict(typ=typ, p1=p1, p2=p2, e1=e1, b2=b2use, size=size, f1=p1['qb'], f2=p2['qa'], qn=qn))
        # inversions: two consecutive strand-change junctions closing on the same contig
        i = 0
        while i < len(js):
            j = js[i]
            if j['typ'] == 'inversion_breakpoint' and i + 1 < len(js) and js[i + 1]['typ'] == 'inversion_breakpoint' and j['p1']['st'] == js[i + 1]['p2']['st'] and j['p1']['tn'] == js[i + 1]['p2']['tn']:
                k = js[i + 1]
                out.append(dict(typ='inversion', size=abs(j['p2']['tb'] - j['p2']['ta']), qn=qn, ids=(j['p1']['id'], j['p2']['id'], k['p2']['id']),
                                fpts=[j['f1'], j['f2'], k['f1'], k['f2']], opts=[(j['p1']['tn'], j['e1']), (j['p2']['tn'], j['b2']), (k['p1']['tn'], k['e1']), (k['p2']['tn'], k['b2'])]))
                i += 2; continue
            if j['typ']:
                out.append(dict(typ=j['typ'], size=j['size'], qn=qn, ids=(j['p1']['id'], j['p2']['id']), fpts=[j['f1'], j['f2']],
                                opts=[(j['p1']['tn'], j['e1']), (j['p2']['tn'], j['b2'])]))
            i += 1
    return out
for focus, plist in (('A', pieces), ('B', [swapped(p) for p in pieces])):
    for e in junctions(plist, focus):
        key = tuple(sorted(e['ids']))
        if key in seen: continue
        seen.add(key); e['focus'] = focus; events.append(e)
labels = {'A': o.a, 'B': o.b}
with open(o.out, 'w') as out:
    out.write('id\ttype\tfocus\tfocus_assembly\tfocus_contig\tfocus_points\tother_assembly\tother_points\tsize\tpieces\n')
    for n, e in enumerate(events, 1):
        f = e['focus']; other = 'B' if f == 'A' else 'A'
        out.write('\t'.join([
            'D%04d' % n, '%s_in_%s' % (e['typ'], f), f, labels[f], e['qn'], ','.join(str(x) for x in e['fpts']), labels[other],
            ','.join('%s:%d' % (c, p) for c, p in e['opts']), str(e['size']), ','.join(str(i) for i in e['ids'])]) + '\n')
if o.stats:
    import json
    qa = collections.defaultdict(list)
    for p in pieces: qa[p['qn']].append((p['qa'], p['qb']))
    def un(iv):
        iv.sort(); t = 0; cs, ce = iv[0]
        for s, e in iv[1:]:
            if s <= ce: ce = max(ce, e)
            else: t += ce - cs; cs, ce = s, e
        return t + ce - cs
    st = dict(pieces=len(pieces), contigs_of_A_with_pieces=len(qa), bases_of_A_in_pieces=sum(un(v) for v in qa.values()), events=len(events),
              min_sv=o.min_sv, min_piece=o.min_piece, end_tol=o.end_tol, max_local=o.max_local)
    json.dump(st, open(o.stats, 'w'), indent=1)
print('pieces', len(pieces), 'events', len(events))
