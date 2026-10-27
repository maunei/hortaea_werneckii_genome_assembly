#!/usr/bin/env python
"""Step 07b: what the 22 sequences are (present in the GitHub file of Hw 2.0, absent from the NCBI record).
Usage: 07_the22.py FASTA IDS_TSV OUTDIR WORKDIR THREADS      (FASTA = Hw 2.0 file; IDS_TSV = the22_ids.tsv written by step 07a)
Environment: QC_BIN, BLAST_BIN, DBS, INPUT, SWISSPROT_FUNGI; optional DEPTH_DIR (output of scripts/07_depth.sh for Hw 2.0), MITO_SUMMARY (summary.json of 07_mito for Hw 2.0), SCREEN_TSV (table of the contaminant screen of contigs).
Per sequence: length, GC, best alignment to the other contigs (identity, coverage), alignment to the NCBI mitochondrion record, genes (miniprot of fungal Swiss-Prot
proteins; tblastn with genetic code 4 of mitochondrial proteins), ribosomal DNA (blastn), PacBio depth relative to the nuclear median, contaminant screen (when available).
Evidence tags: copy_of_other_contigs_98 (>= 90 % of the sequence aligned to other contigs at >= 98 % identity), similar_to_other_contigs (>= 90 % aligned at lower identity), ribosomal_DNA (>= 500 bases aligned to a ribosomal DNA record),
protein_hit (a Swiss-Prot protein covered >= 50 % at >= 35 % identity), mitochondrial_evidence (a core mitochondrial gene family or >= 50 % aligned to the NCBI mitochondrion), vector_marker_bla (>= 50 % of the TEM-1 beta-lactamase protein of cloning vectors aligned), high_copy_depth (depth ratio of reads of mapping quality >= 20 is >= 3)."""
import json, os, sys, glob, statistics, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw07_common import *
from importlib import import_module
import pandas as pd
fasta, ids_tsv, out, work, threads = sys.argv[1:6]; threads = int(threads)
QC, BL, DBS, INPUT = os.environ["QC_BIN"], os.environ["BLAST_BIN"], os.environ["DBS"], os.environ["INPUT"]
SP = os.environ.get("SWISSPROT_FUNGI", f"{DBS}/proteins/swissprot_fungi.faa")
os.makedirs(out, exist_ok=True); os.makedirs(work, exist_ok=True)
ids = pd.read_csv(ids_tsv, sep="\t"); names = list(ids.contig)
allseq = read_fasta(fasta); q = {n: allseq[n] for n in names}
write_fasta(f"{work}/the22.fa", q)
T = pd.DataFrame(dict(sequence=names, length=[len(q[n]) for n in names], gc=[round(gc_fraction(q[n]), 4) for n in names],
                      md5=[md5(q[n]) for n in names], soft_masked_fraction=[round(sum(c.islower() for c in q[n]) / len(q[n]), 4) for n in names]))

# ---- 1. alignment to the other contigs of Hw 2.0 (self alignments removed)
mod = import_module("07_the22_align")
A = mod.align_the22("hw2", fasta, f"{work}/the22.fa", out, threads, exclude_self=True)
A = A.rename(columns={c: "other_contigs_" + c for c in A.columns if c != "sequence"}).drop(columns=["other_contigs_length"])
T = T.merge(A, on="sequence")

# ---- 2. alignment to the mitochondrion record of NCBI
nc = glob.glob(f"{INPUT}/hw2/ncbi_GCA_002127715.1/*_genomic.fna.gz")[0]
rep = glob.glob(f"{INPUT}/hw2/ncbi_GCA_002127715.1/*_assembly_report.txt")[0]
macc = [l.split("\t")[4] for l in open(rep, newline=None).read().splitlines() if not l.startswith("#") and l.split("\t")[7] == "non-nuclear"][0]
write_fasta(f"{work}/ncbi_mito.fa", {macc: read_fasta(nc)[macc].upper()})
paf = run([f"{QC}/minimap2", "-x", "asm20", "-c", "-N", "50", "-t", str(threads), f"{work}/ncbi_mito.fa", f"{work}/the22.fa"])
open(f"{out}/the22_vs_ncbi_mito.paf", "w").write(paf); pr = read_paf(f"{out}/the22_vs_ncbi_mito.paf")
mc, mi = [], []
for n in names:
    hs = [r for r in pr if r["qname"] == n]; L = len(q[n])
    mc.append(round(union_length([(r["qstart"], r["qend"]) for r in hs]) / L, 4) if hs else 0.0)
    mi.append(round(sum(r["nmatch"] for r in hs) / sum(r["alnlen"] for r in hs), 4) if hs else float("nan"))
T["ncbi_mito_aligned_fraction"] = mc; T["ncbi_mito_identity"] = mi

# ---- 3a. nuclear proteins (miniprot, Swiss-Prot fungi)
heads = {}
for line in open(SP):
    if line.startswith(">"):
        p = line[1:].split(" ", 1); heads[p[0]] = p[1].split(" OS=")[0].strip() if len(p) > 1 else ""
mp = run([f"{BL}/miniprot", "-t", str(threads), "--outs=0.5", f"{work}/the22.fa", SP])
open(f"{out}/the22_miniprot.paf", "w").write(mp)
rows = []
for l in mp.strip().split("\n"):
    if not l: continue
    p = l.split("\t"); tg = {t.split(":")[0]: t.split(":", 2)[2] for t in p[12:]}
    qlen, qs, qe, nmatch, alnlen = int(p[1]), int(p[2]), int(p[3]), int(p[9]), int(p[10])
    rows.append(dict(sequence=p[5], protein=p[0], description=heads.get(p[0], ""), protein_length=qlen, protein_coverage=round((qe - qs) / qlen, 3),
                     identity=round(nmatch / alnlen, 3) if alnlen else 0, score=int(tg.get("AS", 0)), frameshifts=int(tg.get("fs", 0)), stop_codons=int(tg.get("st", 0)),
                     tstart=int(p[7]), tend=int(p[8])))
MP = pd.DataFrame(rows, columns=["sequence", "protein", "description", "protein_length", "protein_coverage", "identity", "score", "frameshifts", "stop_codons", "tstart", "tend"])
MPf = MP[(MP.protein_coverage >= 0.5) & (MP.identity >= 0.35)].sort_values(["sequence", "score"], ascending=[True, False])
MPf.to_csv(f"{out}/the22_proteins_swissprot.tsv", sep="\t", index=False)
T["swissprot_proteins_aligned"] = [int(MPf[MPf.sequence == n].protein.nunique()) for n in names]
T["swissprot_best_protein"] = [(MPf[MPf.sequence == n].iloc[0].protein + " " + MPf[MPf.sequence == n].iloc[0].description) if (MPf.sequence == n).any() else "none" for n in names]
T["swissprot_best_identity"] = [(MPf[MPf.sequence == n].iloc[0].identity) if (MPf.sequence == n).any() else float("nan") for n in names]

# ---- 3b. mitochondrial proteins (tblastn, genetic code 4)
CORE = ["nad1", "nad2", "nad3", "nad4", "nad4l", "nad5", "nad6", "cox1", "cox2", "cox3", "cob", "atp6", "atp8", "atp9"]; ALIAS = {"cytb": "cob", "oli1": "atp9"}
run([f"{BL}/makeblastdb", "-in", f"{work}/the22.fa", "-dbtype", "nucl", "-out", f"{work}/db22", "-logfile", f"{work}/mdb.log"])
tb = run([f"{BL}/tblastn", "-query", f"{DBS}/mito_refs/mito_proteins.faa", "-db", f"{work}/db22", "-db_gencode", "4", "-evalue", "1e-10",
          "-outfmt", "6 qseqid sseqid pident length qlen qstart qend sstart send evalue bitscore", "-num_threads", str(threads), "-seg", "no"])
open(f"{out}/the22_tblastn_mito.tsv", "w").write("qseqid\tsseqid\tpident\tlength\tqlen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore\n" + tb)
cov = {}
for h in [l.split("\t") for l in tb.strip().split("\n") if l]:
    cov.setdefault((h[1], h[0]), []).append((int(h[5]) - 1, int(h[6]), int(h[4])))
fam = {n: set() for n in names}; anyhit = {n: set() for n in names}
for (c, qq), iv in cov.items():
    g = ALIAS.get(qq.split("|")[1].lower().replace("_", ""), qq.split("|")[1].lower().replace("_", ""))
    if g not in CORE: continue
    anyhit[c].add(g)
    if union_length([(a, b) for a, b, _ in iv]) / iv[0][2] >= 0.5: fam[c].add(g)
T["mito_core_families_found"] = [len(fam[n]) for n in names]; T["mito_core_families"] = [";".join(sorted(fam[n])) for n in names]

# ---- 3c. ribosomal DNA (blastn of three Hortaea werneckii ribosomal DNA records)
rd = f"{DBS}/rdna_refs/rdna_hw.fasta"
if os.path.exists(rd):
    bn = run([f"{BL}/blastn", "-query", rd, "-db", f"{work}/db22", "-evalue", "1e-20", "-outfmt", "6 qseqid sseqid pident length qlen qstart qend sstart send evalue bitscore", "-dust", "no"])
    open(f"{out}/the22_blastn_rdna.tsv", "w").write("qseqid\tsseqid\tpident\tlength\tqlen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore\n" + bn)
    iv = {n: [] for n in names}
    for h in [l.split("\t") for l in bn.strip().split("\n") if l]:
        a, b = sorted((int(h[7]), int(h[8]))); iv[h[1]].append((a - 1, b))
    T["rdna_bases_aligned"] = [union_length(iv[n]) for n in names]
else:
    T["rdna_bases_aligned"] = float("nan")

# ---- 3d. vector marker: beta-lactamase TEM-1 (tblastn, standard genetic code)
bl = f"{DBS}/rdna_refs/vector_marker_bla.faa"
if os.path.exists(bl):
    vb = run([f"{BL}/tblastn", "-query", bl, "-db", f"{work}/db22", "-evalue", "1e-20", "-outfmt", "6 qseqid sseqid pident length qlen qstart qend sstart send evalue bitscore", "-seg", "no"])
    open(f"{out}/the22_tblastn_bla.tsv", "w").write("qseqid\tsseqid\tpident\tlength\tqlen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore\n" + vb)
    vcov = {n: [] for n in names}
    for h in [l.split("\t") for l in vb.strip().split("\n") if l]: vcov[h[1]].append((int(h[5]) - 1, int(h[6]), int(h[4])))
    T["bla_marker_protein_coverage"] = [round(union_length([(a, b) for a, b, _ in vcov[n]]) / vcov[n][0][2], 3) if vcov[n] else 0.0 for n in names]
else:
    T["bla_marker_protein_coverage"] = float("nan")

# ---- 4. depth relative to the nuclear median
D = os.environ.get("DEPTH_DIR", "")
if D and os.path.exists(f"{D}/depth.regions.bed.gz") and os.path.exists(f"{D}/depth.per_contig.tsv"):
    win = read_window_depth(f"{D}/depth.regions.bed.gz"); pc = pd.read_csv(f"{D}/depth.per_contig.tsv", sep="\t"); md = dict(zip(pc.contig, pc.mean_depth)); mq = dict(zip(pc.contig, pc.mean_depth_mapq20))
    excl = set(names)
    ms = os.environ.get("MITO_SUMMARY", "")
    if ms and os.path.exists(ms): excl |= set(json.load(open(ms))["mitochondrial_contig_names"])
    else: excl.add("unitig_320")
    nm = nuclear_median(win, excl)
    T["mean_depth"] = [md.get(n, 0.0) for n in names]
    T["depth_ratio_mapq20_to_nuclear_median"] = [round(mq.get(n, 0.0) / nm, 3) for n in names]
    T["depth_ratio_to_nuclear_median"] = [round(md.get(n, 0.0) / nm, 3) for n in names]
    nuclear_median_value = nm
else:
    T["mean_depth"] = float("nan"); T["depth_ratio_to_nuclear_median"] = float("nan"); T["depth_ratio_mapq20_to_nuclear_median"] = float("nan"); nuclear_median_value = None

# ---- 4b. evidence tags (mechanical summary of the columns; thresholds fixed here)
def tags(r):
    t = []
    if r.other_contigs_aligned_fraction_identity_ge_0_98 >= 0.9: t.append("copy_of_other_contigs_98")
    elif r.other_contigs_aligned_fraction >= 0.9: t.append("similar_to_other_contigs")
    if r.rdna_bases_aligned == r.rdna_bases_aligned and r.rdna_bases_aligned >= 500: t.append("ribosomal_DNA")
    if r.swissprot_proteins_aligned >= 1: t.append("protein_hit")
    if r.bla_marker_protein_coverage == r.bla_marker_protein_coverage and r.bla_marker_protein_coverage >= 0.5: t.append("vector_marker_bla")
    if r.mito_core_families_found >= 1 or r.ncbi_mito_aligned_fraction >= 0.5: t.append("mitochondrial_evidence")
    if r.depth_ratio_mapq20_to_nuclear_median == r.depth_ratio_mapq20_to_nuclear_median and r.depth_ratio_mapq20_to_nuclear_median >= 3: t.append("high_copy_depth")
    return ";".join(t) if t else "no_evidence"
T["evidence_tags"] = [tags(r) for r in T.itertuples()]

# ---- 5. contaminant screen of contigs (when delivered)
S = os.environ.get("SCREEN_TSV", "")
if S and os.path.exists(S):
    st = pd.read_csv(S, sep="\t")
    T["contaminant_screen"] = "see " + os.path.basename(S)
    T = T.merge(st, left_on="sequence", right_on=st.columns[0], how="left", suffixes=("", "_screen"))
else:
    T["contaminant_screen"] = "not run"
T.to_csv(f"{out}/the22_table.tsv", sep="\t", index=False)
# nuclear GC for context
nuc = [n for n in allseq if n not in set(names) and n != "unitig_320"]
gcn = sum(gc_fraction(allseq[n]) * len(allseq[n]) for n in nuc) / sum(len(allseq[n]) for n in nuc)
summary = dict(sequences=len(T), total_bases=int(T.length.sum()), min_length=int(T.length.min()), max_length=int(T.length.max()),
               nuclear_gc_length_weighted=round(gcn, 4), gc_min=float(T.gc.min()), gc_max=float(T.gc.max()),
               with_mito_alignment_ge_0_5=int((T.ncbi_mito_aligned_fraction >= 0.5).sum()),
               with_mito_core_family=int((T.mito_core_families_found >= 1).sum()),
               other_contigs_coverage_ge_0_9=int((T.other_contigs_aligned_fraction >= 0.9).sum()),
               other_contigs_coverage_ge_0_9_at_identity_ge_0_98=int((T.other_contigs_aligned_fraction_identity_ge_0_98 >= 0.9).sum()),
               with_rdna_alignment=int((T.rdna_bases_aligned > 0).sum()) if T.rdna_bases_aligned.notna().all() else None,
               evidence_tag_counts=T.evidence_tags.str.split(";").explode().value_counts().to_dict(),
               with_vector_marker_bla=int((T.bla_marker_protein_coverage >= 0.5).sum()) if T.bla_marker_protein_coverage.notna().all() else None,
               with_swissprot_protein=int((T.swissprot_proteins_aligned >= 1).sum()),
               depth_reads_file=(open(f"{D}/reads_used.txt").read().strip().split("/")[-1] if D and os.path.exists(f"{D}/reads_used.txt") else None),
               depth_available=nuclear_median_value is not None, nuclear_median_window_depth=nuclear_median_value,
               depth_ratio_min=float(T.depth_ratio_to_nuclear_median.min()) if nuclear_median_value else None,
               depth_ratio_max=float(T.depth_ratio_to_nuclear_median.max()) if nuclear_median_value else None,
               contaminant_screen=("done" if S and os.path.exists(S) else "not run"))
json.dump(summary, open(f"{out}/summary.json", "w"), indent=1, default=lambda x: None if x != x else str(x))
print(T.to_string()); print(summary)
