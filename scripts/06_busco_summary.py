"""Step 06, line 2: BUSCO result of one assembly (lineage fungi_odb10, genome mode).
Usage: 06_busco_summary.py SHORT_SUMMARY.txt FULL_TABLE.tsv OUT_PREFIX
Counts come from the full table (one status per BUSCO gene: Complete, Duplicated, Fragmented, Missing); the percentages are checked against the line 'C:..%[S:..%,D:..%],F:..%,M:..%,n:..' of the short summary.
complete = single + duplicated.
"""
import sys, re, json, collections
ss, ft, prefix = sys.argv[1:4]
cnt = collections.Counter(); seen = {}
for l in open(ft):
    if l.startswith('#') or not l.strip(): continue
    x = l.rstrip('\n').split('\t'); seen[x[0]] = x[1]
for v in seen.values(): cnt[v] += 1
n = len(seen); S, D, F, M = cnt['Complete'], cnt['Duplicated'], cnt['Fragmented'], cnt['Missing']
t = open(ss).read(); m = re.search(r'C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)', t)
assert m and int(m.group(6)) == n and abs(float(m.group(1)) - 100 * (S + D) / n) < 0.1, 'full table and short summary disagree'
res = dict(busco_genes=n, complete=S + D, complete_single=S, complete_duplicated=D, fragmented=F, missing=M,
           complete_percent=100 * (S + D) / n, single_percent=100 * S / n, duplicated_percent=100 * D / n, fragmented_percent=100 * F / n, missing_percent=100 * M / n,
           lineage='fungi_odb10', mode='genome')
with open(prefix + '.tsv', 'w') as o:
    o.write('measure\tvalue\n')
    for k, v in res.items(): o.write(f'{k}\t{v}\n')
json.dump(res, open(prefix + '.json', 'w'), indent=1)
