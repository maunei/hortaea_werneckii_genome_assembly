"""Check of the comparison and adjudication (step 07) on a synthetic case in which the true arrangement is known.
  make DIR     writes DIR/A.fa, DIR/B.fa (two assemblies of one synthetic genome, each with different structural errors) and DIR/reads.fastq
               (30-fold PacBio-like reads drawn from the true genome, 12 percent errors: substitutions, deletions and insertions)
  check DIR/out/disagreements.tsv   compares the decisions with the truth and prints one line per planted difference; exit status 1 if any is wrong or missing
Planted differences (A is wrong where the truth is B and the reverse):
  a1:50000 deletion of 2000 bases in A (B right) | a1:150000 insertion of 3000 in A (B right) | a1:250000 insertion of 2500 in B (A right)
  a2:100000 inversion of 10000 in A (B right) | a2:200000 deletion of 1500 in B (A right) | a3a/a3b break in A of one molecule (B right)
  a5 vs b5a/b5b break in B of one molecule (A right) | a6:200000 tandem duplication of 4000 in A (B right) | b6:100000 inversion of 8000 in B (A right)
  a7 holds 30000 bases that b7 lacks (A right) | a8 holds 30000 extra bases that b8 lacks (B right)"""
import sys, random, os
comp = str.maketrans('ACGT', 'TGCA')
rc = lambda s: s.translate(comp)[::-1]
def make(d):
    os.makedirs(d, exist_ok=True); random.seed(5)
    rnd = lambda n: ''.join(random.choice('ACGT') for _ in range(n))
    t1, t2, m3, m5, m6, m7, m8 = rnd(300000), rnd(300000), rnd(500000), rnd(500000), rnd(400000), rnd(300000), rnd(300000)
    truth = {'t1': t1, 't2': t2, 'm3': m3, 'm5': m5, 'm6': m6, 'm7': m7, 'm8': m8}
    ins3, ins2, Y = rnd(3000), rnd(2500), rnd(30000)
    A = {'a1': t1[:50000] + t1[52000:150000] + ins3 + t1[150000:], 'a2': t2[:100000] + rc(t2[100000:110000]) + t2[110000:],
         'a3a': m3[:250000], 'a3b': m3[250000:], 'a5': m5, 'a6': m6[:200000] + m6[196000:200000] + m6[200000:], 'a7': m7, 'a8': m8[:100000] + Y + m8[100000:]}
    B = {'b1': t1[:250000] + ins2 + t1[250000:], 'b2': t2[:200000] + t2[201500:], 'b3': m3, 'b5a': m5[:250000], 'b5b': m5[250000:],
         'b6': m6[:100000] + rc(m6[100000:108000]) + m6[108000:], 'b7': m7[:100000] + m7[130000:], 'b8': m8}
    for name, dd in (('A', A), ('B', B)):
        with open(os.path.join(d, name + '.fa'), 'w') as f:
            for k, v in dd.items(): f.write('>%s\n%s\n' % (k, v))
    tot = sum(len(v) for v in truth.values()); names = list(truth); w = [len(truth[k]) for k in names]
    def mutate(s, rate=0.12):
        out = []
        for c in s:
            r = random.random()
            if r < rate * 0.5: out.append(random.choice('ACGT'))
            elif r < rate * 0.75: pass
            elif r < rate: out.append(c); out.append(random.choice('ACGT'))
            else: out.append(c)
        return ''.join(out)
    n = cov = 0
    with open(os.path.join(d, 'reads.fastq'), 'w') as f:
        while cov < 30 * tot:
            L = max(1500, int(random.gammavariate(3, 2000))); k = random.choices(names, w)[0]; s = truth[k]
            if L >= len(s): continue
            p = random.randrange(0, len(s) - L); r = s[p:p + L]
            if random.random() < 0.5: r = rc(r)
            r = mutate(r); n += 1; cov += L
            f.write('@r%d\n%s\n+\n%s\n' % (n, r, 'I' * len(r)))
# (contig on which the disagreement is listed, type, approximate position, arrangement that the reads must support)
EXPECTED = [('a1', 'deletion_in_A', 50000, 'B'), ('a1', 'insertion_in_A', 150000, 'B'), ('a1', 'deletion_in_A', 250000, 'A'),
            ('a2', 'inversion_in_A', 100000, 'B'), ('a2', 'insertion_in_A', 200000, 'A'), ('b3', 'join_in_B', 250000, 'B'),
            ('a5', 'join_in_A', 250000, 'A'), ('a6', 'insertion_in_A', 198000, 'B'), ('a6', 'inversion_in_A', 100000, 'A'),
            ('a7', 'insertion_in_A', 115000, 'A'), ('a8', 'insertion_in_A', 115000, 'B')]
def check(tsv):
    rows = [l.rstrip('\n').split('\t') for l in open(tsv)]; head = rows[0]; rows = [dict(zip(head, r)) for r in rows[1:]]
    bad = 0; used = set()
    for c, t, pos, win in EXPECTED:
        hit = None
        for i, r in enumerate(rows):
            pts = [int(x) for x in r['focus_points'].split(',')]
            if i not in used and r['focus_contig'] == c and r['type'] == t and min(abs(p - pos) for p in pts) <= 20000 and abs(sum(pts) / len(pts) - pos) <= 20000:
                hit = i; break
        if hit is None: print('MISSING', c, t, pos); bad += 1; continue
        used.add(hit); st = rows[hit]['status']; ok = st == 'decided_' + win
        print('ok  ' if ok else 'WRONG', c, t, pos, 'expected', win, 'got', st, 'reads A/B/neither', rows[hit]['reads_A'], rows[hit]['reads_B'], rows[hit]['reads_neither']); bad += 0 if ok else 1
    extra = len(rows) - len(used)
    print('unexpected extra disagreements:', extra)
    sys.exit(1 if bad or extra else 0)
if __name__ == '__main__':
    if sys.argv[1] == 'make': make(sys.argv[2])
    else: check(sys.argv[2])
