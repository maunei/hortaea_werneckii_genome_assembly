"""Length statistics of a nucleotide FASTA (number of sequences, total length, N50, shortest, longest) written as JSON.
Usage: 06_fasta_stats.py FASTA OUT.json [key=value ...]   (the key=value pairs are copied into the JSON)"""
import sys, json
fa, out = sys.argv[1:3]
extra = dict(a.split('=', 1) for a in sys.argv[3:])
lens = []
n = 0
with open(fa) as fh:
    for line in fh:
        if line.startswith('>'):
            if n: lens.append(n)
            n = 0
        else:
            n += len(line.strip())
if n: lens.append(n)
lens.sort(reverse=True)
tot = sum(lens)
acc = 0
n50 = 0
for l in lens:
    acc += l
    if acc * 2 >= tot:
        n50 = l
        break
res = dict(sequences=len(lens), total_bases=tot, n50=n50, shortest=lens[-1] if lens else 0, longest=lens[0] if lens else 0)
res.update(extra)
json.dump(res, open(out, 'w'), indent=1)
print(res)
