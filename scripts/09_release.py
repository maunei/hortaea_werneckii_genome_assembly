#!/usr/bin/env python3
"""Step 09: the final assembly (Hw 2.1) as files. Writes results/assembly/:
  Hw2.1.fasta.gz        the final assembly: polished with Quiver, contaminant contigs removed (step 05c), no base edited
  Hw2.1_contigs.tsv     every contig: length, class of the contaminant screen, best contaminant, mitochondrial contig or not, md5 of the sequence
The contigs are written from the longest to the shortest and the gzip header holds no time (see the comment below).
Usage: HW=$PWD python3 scripts/09_release.py [ASM]   (default proc_r1; the three runs give the same contigs, see the report)"""
import os, sys, gzip, csv, json, hashlib
from pathlib import Path
HW = Path(os.environ.get('HW', Path(__file__).resolve().parent.parent)); WORK = Path(os.environ['HW_WORK'])
asm = sys.argv[1] if len(sys.argv) > 1 else 'proc_r1'; out = HW / 'results' / 'assembly'; out.mkdir(parents=True, exist_ok=True)
scr = {r['contig']: r for r in csv.DictReader(gzip.open(HW / 'results/02_pacbio_reads/screen_contigs' / asm / f'{asm}_per_contig.tsv.gz', 'rt'), delimiter='\t')}
mito = set(json.load(open(HW / 'results/07_comparator/mito' / asm / 'summary.json')).get('mitochondrial_contig_names', []))
def records(p):
    n = None; s = []
    for l in open(p):
        if l[0] == '>':
            if n is not None: yield n, ''.join(s)
            n = l[1:].split()[0]; s = []
        else: s.append(l.strip())
    if n is not None: yield n, ''.join(s)
def wrap(s): return '\n'.join(s[i:i + 80] for i in range(0, len(s), 80))
# Deterministic output. The contigs keep the names that the assembler (Canu) gave them. They are written from the longest to the shortest (equal lengths: by name),
# and the gzip header holds no time, so that the same contigs give the same file in every run. Canu can number two contigs in a different order in two runs on the
# same data (two contigs exchanged their names in some runs); then the file differs in those two names only. The assembly is identified by the checksum of its
# sequences, names and orientation ignored (results/09_summary/replicate_check.tsv, last column), which step 10 compares with the expected value.
recs = [(name, s) for name, s in records(WORK / 'asm' / asm / 'final.fasta')]
recs.sort(key=lambda r: (-len(r[1]), r[0]))
with open(out / 'Hw2.1.fasta.gz', 'wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=6) as fa, open(out / 'Hw2.1_contigs.tsv', 'w') as t:
    t.write('contig\tlength\tscreen_class\tbest_contaminant\tmitochondrial\tmd5\n')
    for name, s in recs:
        c = scr[name]; fa.write(f'>{name}\n{wrap(s)}\n'.encode())
        org = c['best_contaminant_organism'] if c['class'] not in ('fungal_match_only_kept', 'no_match_kept') else ''
        t.write(f"{name}\t{len(s)}\t{c['class']}\t{org}\t{'yes' if name in mito else 'no'}\t{hashlib.md5(s.encode()).hexdigest()}\n")
print(asm, len(recs), 'contigs written to', out)
