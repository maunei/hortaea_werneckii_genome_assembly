#!/usr/bin/env python
"""Step 07b: alignment of the 22 sequences (present in the GitHub file of Hw 2.0, absent from the NCBI record) to the contigs of an assembly.
Usage: 07_the22_align.py ASM TARGET_FASTA QUERY_FASTA OUTDIR THREADS [exclude_self]
  ASM          name of the assembly (label)
  TARGET_FASTA the assembly the sequences are aligned to ('final.fasta' of any assembly)
  QUERY_FASTA  FASTA of the 22 sequences
  exclude_self 'exclude_self' discards alignments of a sequence to the contig of the same name (used when the target is Hw 2.0 itself)
Output: OUTDIR/the22_vs_<ASM>.paf, OUTDIR/the22_vs_<ASM>.tsv (per sequence: aligned fraction, best contig, identity, aligned fraction at identity >= 0.98 and >= 0.90).
Alignment: minimap2 preset asm20 (up to about 20 % divergence), all alignments kept (up to 50 secondary), base-level."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw07_common import *
import pandas as pd

def align_the22(asm, target, query, out, threads, exclude_self=False, mm2=None, label=None):
    mm2 = mm2 or os.environ["QC_BIN"] + "/minimap2"
    label = label or asm
    os.makedirs(out, exist_ok=True)
    paf = run([mm2, "-x", "asm20", "-c", "--cs", "-N", "50", "-p", "0.1", "-t", str(threads), target, query])
    pf = f"{out}/the22_vs_{label}.paf"; open(pf, "w").write(paf)
    rows = read_paf(pf)
    if exclude_self: rows = [r for r in rows if r["qname"] != r["tname"]]
    qs = read_fasta(query)
    res = []
    for q, s in qs.items():
        hs = [r for r in rows if r["qname"] == q]
        L = len(s)
        cov = lambda sel: union_length([(r["qstart"], r["qend"]) for r in sel]) / L if sel else 0.0
        ident = lambda r: r["nmatch"] / r["alnlen"]
        hi98 = [r for r in hs if ident(r) >= 0.98]; hi90 = [r for r in hs if ident(r) >= 0.90]
        if hs:
            best = max(hs, key=lambda r: r["alnlen"])
            by_t = {}
            for r in hs: by_t.setdefault(r["tname"], []).append(r)
            tbest = max(by_t, key=lambda t: sum(r["alnlen"] for r in by_t[t]))
            tcov = cov(by_t[tbest])
            tid = sum(r["nmatch"] for r in by_t[tbest]) / sum(r["alnlen"] for r in by_t[tbest])
            res.append(dict(sequence=q, length=L, aligned_fraction=round(cov(hs), 4), aligned_fraction_identity_ge_0_98=round(cov(hi98), 4),
                            aligned_fraction_identity_ge_0_90=round(cov(hi90), 4), best_contig=tbest, best_contig_aligned_fraction=round(tcov, 4),
                            best_contig_identity=round(tid, 4), best_contig_length=best["tlen"], n_alignments=len(hs),
                            n_contigs_hit=len(by_t)))
        else:
            res.append(dict(sequence=q, length=L, aligned_fraction=0.0, aligned_fraction_identity_ge_0_98=0.0, aligned_fraction_identity_ge_0_90=0.0,
                            best_contig="none", best_contig_aligned_fraction=0.0, best_contig_identity=float("nan"), best_contig_length=0, n_alignments=0, n_contigs_hit=0))
    df = pd.DataFrame(res); df.to_csv(f"{out}/the22_vs_{label}.tsv", sep="\t", index=False)
    return df

if __name__ == "__main__":
    asm, target, query, out, threads = sys.argv[1:6]
    df = align_the22(asm, target, query, out, int(threads), exclude_self=(len(sys.argv) > 6 and sys.argv[6] == "exclude_self"))
    print(df.to_string())
