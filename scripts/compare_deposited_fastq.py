"""Compares the filtered subreads made in step 02 with the FASTQ file that the authors deposited (bz2). Reads are matched by name
(movie/hole/start_end) and the sequences of matched reads are compared. Usage: compare_deposited_fastq.py OURS.fastq DEPOSITED.fastq.bz2 OUT.json"""
import sys, bz2, json, hashlib
def reads(fh):
    while True:
        h = fh.readline()
        if not h: return
        s = fh.readline().strip(); fh.readline(); q = fh.readline().strip()
        yield h[1:].split()[0], s, q
def hole(n):
    m, h, c = n.split('/'); return (m, h)
ours = {}; dep = {}; first = []
with open(sys.argv[1]) as f:
    for n, s, q in reads(f): ours[n] = s
with bz2.open(sys.argv[2], 'rt') as f:
    for n, s, q in reads(f):
        dep[n] = s
        if len(first) < 3: first.append(n)
oh = {}; dh = {}
for n in ours: oh.setdefault(hole(n), []).append(n)
for n in dep: dh.setdefault(hole(n), []).append(n)
identical = [n for n in ours if n in dep and ours[n] == dep[n]]
only_o = [n for n in ours if n not in dep]; only_d = [n for n in dep if n not in ours]
# reads that differ only in the end coordinate: same hole and start, the shorter sequence is contained in the longer one
near = 0
for n in only_o:
    m, h, c = n.split('/'); st = c.split('_')[0]
    for d in dh.get(hole(n), []):
        if d.split('/')[2].split('_')[0] == st and (ours[n].startswith(dep[d]) or dep[d].startswith(ours[n])): near += 1; break
out = dict(reads_ours=len(ours), reads_deposited=len(dep), holes_ours=len(oh), holes_deposited=len(dh), holes_in_both=len(set(oh) & set(dh)),
           identical_reads=len(identical), reads_only_ours=len(only_o), reads_only_deposited=len(only_d),
           only_ours_same_start_one_contains_other=near, holes_only_ours=len(set(oh) - set(dh)), holes_only_deposited=len(set(dh) - set(oh)),
           reads_in_holes_only_ours=sum(len(oh[h]) for h in set(oh) - set(dh)), example_deposited_names=first)
json.dump(out, open(sys.argv[3], 'w'), indent=1); print(json.dumps(out, indent=1))
