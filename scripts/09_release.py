#!/usr/bin/env python3
"""Step 09: the final assembly (Hw 2.1) as files. Writes results/assembly/:
  Hw2.1.fasta.gz        the final assembly: polished with Quiver, contaminant contigs removed (step 05c), no base edited
  Hw2.1_contigs.tsv     every contig: new name, name given by the assembler, length, class of the contaminant screen, best contaminant, mitochondrial contig or not, md5 of the sequence
The contigs are named Hw2.1_001, Hw2.1_002, ... from the longest to the shortest (equal lengths: by the md5 of the sequence), and the gzip header holds no time,
so that the same sequences give the same file, byte by byte, in every run.
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
# Deterministic output. The program that assembles the contigs (Canu) numbers them in an order that can differ between two runs on the same data
# (two contigs exchanged their names in some runs), and gzip writes the time into its header. Therefore the contigs are put in order of length
# (longest first; equal lengths by the md5 of the sequence) and named by that order; the name given by the assembler is kept in the table.
# The same sequences then give the same file, byte by byte, in every run.
recs = []
for name, s in records(WORK / 'asm' / asm / 'final.fasta'):
    recs.append((-len(s), hashlib.md5(s.encode()).hexdigest(), name, s))
recs.sort(key=lambda r: (r[0], r[1]))
width = max(3, len(str(len(recs))))
with open(out / 'Hw2.1.fasta.gz', 'wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=6) as fa, open(out / 'Hw2.1_contigs.tsv', 'w') as t:
    t.write('contig\tassembler_name\tlength\tscreen_class\tbest_contaminant\tmitochondrial\tmd5\n')
    for i, (neg, md5, name, s) in enumerate(recs, 1):
        c = scr[name]; new = f'Hw2.1_{i:0{width}d}'; fa.write(f'>{new}\n{wrap(s)}\n'.encode())
        org = c['best_contaminant_organism'] if c['class'] not in ('fungal_match_only_kept', 'no_match_kept') else ''
        t.write(f"{new}\t{name}\t{-neg}\t{c['class']}\t{org}\t{'yes' if name in mito else 'no'}\t{md5}\n")
print(asm, len(recs), 'contigs written to', out)
