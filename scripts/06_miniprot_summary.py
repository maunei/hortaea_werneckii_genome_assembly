"""Step 06, line 2: Swiss-Prot fungal proteins aligned to one assembly with miniprot (protein-to-genome alignment; amino-acid level).
Usage: 06_miniprot_summary.py MINIPROT.paf ASSEMBLY_TOTAL_BP OUT_PREFIX [MIN_COVERAGE=0.9] [HIGH_IDENTITY=0.7]
The PAF comes from miniprot -u --outn=1, so every protein has one line: its best alignment, or a line with strand '*' if it did not align.
  coverage        (query end - query start) / protein length of the best alignment.
  whole           coverage of at least MIN_COVERAGE (default 0.9): the protein is found in one piece along its whole length.
  intact          whole, with no frameshift (tag fs) and no in-frame stop codon (tag st) in the alignment.
  amino-acid identity  identical residues / residues of the protein that are aligned (query end - query start). Identical residues are read from the cs tag of the PAF line (the ':N' runs of identical residues).
Frameshifts and premature stop codons per megabase are counted over whole alignments after the removal of repeated loci: many Swiss-Prot proteins are homologues of one gene, so the whole alignments are
sorted by score (tag AS) and one is kept only if less than half of its target interval is already taken by a kept alignment. The denominator is the coding sequence of the kept alignments
(aligned residues x 3); the count per megabase of assembly is given as well.
Because an alignment of a distant protein can place a frameshift only to explain differences between species, the same counts are also given for the kept alignments with an amino-acid identity of at least HIGH_IDENTITY (default 0.7), where such artefacts are rare (keys ending in _high_identity).
Writes OUT_PREFIX_proteins.tsv.gz (one row per protein) and OUT_PREFIX.json.
"""
import sys, gzip, json, re
import numpy as np
paf, total_bp, prefix = sys.argv[1], int(sys.argv[2]), sys.argv[3]
mincov = float(sys.argv[4]) if len(sys.argv) > 4 else 0.9
highid = float(sys.argv[5]) if len(sys.argv) > 5 else 0.7
rows = []
with open(paf) as f:
    for l in f:
        x = l.rstrip('\n').split('\t')
        qn, ql = x[0], int(x[1])
        if x[4] == '*': rows.append(dict(protein=qn, length=ql, aligned=False)); continue
        tags = {t[:2]: t[5:] for t in x[12:] if t[2:5] in (':i:', ':f:', ':Z:')}
        qs, qe = int(x[2]), int(x[3]); alen = qe - qs
        same = sum(int(v) for v in re.findall(r':(\d+)', tags.get('cs', '')))
        rows.append(dict(protein=qn, length=ql, aligned=True, qs=qs, qe=qe, strand=x[4], contig=x[5], ts=int(x[7]), te=int(x[8]), cov=(qe - qs) / ql,
                         ident=same / alen if alen else 0.0, score=int(tags.get('AS', 0)), fs=int(tags.get('fs', 0)), st=int(tags.get('st', 0))))
n = len(rows); al = [r for r in rows if r['aligned']]
whole = [r for r in al if r['cov'] >= mincov]
intact = [r for r in whole if r['fs'] == 0 and r['st'] == 0]
# one alignment per locus
taken = {}; kept = []
for r in sorted(whole, key=lambda r: -r['score']):
    if r['contig'] not in taken: taken[r['contig']] = {}
    iv = taken[r['contig']]
    # interval bookkeeping on a sorted list of kept (start, end) intervals per contig: overlap computed directly (the number of kept alignments per contig is small)
    ov = 0
    for s, e in iv.get('l', []):
        ov += max(0, min(e, r['te']) - max(s, r['ts']))
    if ov < 0.5 * (r['te'] - r['ts']):
        iv.setdefault('l', []).append((r['ts'], r['te'])); kept.append(r); r['kept'] = True
for r in rows: r.setdefault('kept', False)
coding = sum((r['qe'] - r['qs']) * 3 for r in kept)
fs = sum(r['fs'] for r in kept); st = sum(r['st'] for r in kept)
hk = [r for r in kept if r['ident'] >= highid]
coding_h = sum((r['qe'] - r['qs']) * 3 for r in hk); fs_h = sum(r['fs'] for r in hk); st_h = sum(r['st'] for r in hk)
with gzip.open(prefix + '_proteins.tsv.gz', 'wt') as o:
    o.write('protein\tlength_aa\taligned\tcoverage\tidentity\tframeshifts\tstop_codons\twhole\tkept_locus\tcontig\ttarget_start\ttarget_end\n')
    for r in rows:
        if r['aligned']:
            o.write(f"{r['protein']}\t{r['length']}\t1\t{r['cov']:.4f}\t{r['ident']:.4f}\t{r['fs']}\t{r['st']}\t{int(r['cov'] >= mincov)}\t{int(r['kept'])}\t{r['contig']}\t{r['ts']}\t{r['te']}\n")
        else:
            o.write(f"{r['protein']}\t{r['length']}\t0\tNA\tNA\tNA\tNA\t0\t0\tNA\tNA\tNA\n")
res = dict(proteins_total=n, proteins_aligned=len(al), proteins_whole=len(whole), frac_proteins_whole=len(whole) / n if n else None,
           proteins_intact=len(intact), frac_proteins_intact=len(intact) / n if n else None,
           median_identity_whole=float(np.median([r['ident'] for r in whole])) if whole else None,
           loci_kept=len(kept), coding_bases_kept=coding, frameshifts_in_kept=fs, stop_codons_in_kept=st,
           frameshifts_per_mb_coding=1e6 * fs / coding if coding else None, stop_codons_per_mb_coding=1e6 * st / coding if coding else None,
           frameshifts_per_mb_assembly=1e6 * fs / total_bp, stop_codons_per_mb_assembly=1e6 * st / total_bp, min_coverage_for_whole=mincov,
           loci_kept_high_identity=len(hk), coding_bases_kept_high_identity=coding_h, frameshifts_high_identity=fs_h, stop_codons_high_identity=st_h,
           frameshifts_per_mb_coding_high_identity=1e6 * fs_h / coding_h if coding_h else None, stop_codons_per_mb_coding_high_identity=1e6 * st_h / coding_h if coding_h else None, min_identity_for_high=highid)
json.dump(res, open(prefix + '.json', 'w'), indent=1)
