#!/usr/bin/env python
"""Step 07c: recognise and describe the mitochondrial genome of one assembly.
Usage: 07_mito.py ASM FASTA OUTDIR WORKDIR THREADS      (tool folders and database folder are read from the environment: QC_BIN, BLAST_BIN, DBS, INPUT)
Optional environment: DEPTH_DIR (folder with depth.regions.bed.gz and depth.per_contig.tsv from scripts/07_depth.sh; read depth is skipped when absent).

Evidence per contig
  1. protein: tblastn (genetic code 4, mould mitochondrion; e-value 1e-10) of the mitochondrial proteins of the reference fungi; a core gene family
     (nad1-6, nad4L, cox1-3, cob, atp6, atp8, atp9) counts as found when at least 50 % of one reference protein is covered by hits on the contig.
  2. genome: bases of the contig aligned (minimap2 preset asm20) to the mitochondrial genomes of the reference fungi.
  3. depth: mean PacBio depth of the contig divided by the median depth of 1-kb windows of the nuclear contigs.
Classes (fixed): mitochondrial = at least MIN_FAMILIES (4) core families found; candidate = at least one core family or 1,000 aligned genome bases, and
  depth ratio of at least 3 (when depth is available; without depth the contig is listed as 'candidate_no_depth'); everything else nuclear.
Circularity: overlap of the two ends of the contig (exact and aligned)."""
import json, os, sys, glob, re, subprocess, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw07_common import *
import pandas as pd

asm, fasta, out, work, threads = sys.argv[1:6]; threads = int(threads)
QC, BL, DBS, INPUT = os.environ["QC_BIN"], os.environ["BLAST_BIN"], os.environ["DBS"], os.environ["INPUT"]
MIN_FAMILIES, MIN_GENOME_BP, MIN_RATIO, MIN_PROT_COV = 4, 1000, 3.0, 0.5
CORE = ["nad1", "nad2", "nad3", "nad4", "nad4l", "nad5", "nad6", "cox1", "cox2", "cox3", "cob", "atp6", "atp8", "atp9"]
ALIAS = {"cytb": "cob", "oli1": "atp9"}
os.makedirs(out, exist_ok=True); os.makedirs(work, exist_ok=True)
refdir = f"{DBS}/mito_refs"
seqs = read_fasta(fasta)
L = {n: len(s) for n, s in seqs.items()}
GC = {n: gc_fraction(s) for n, s in seqs.items()}

def family(qid):
    g = qid.split("|")[1].lower().replace("_", "")
    g = ALIAS.get(g, g)
    return g if g in CORE else None

# ---- 1. protein evidence
run([f"{BL}/makeblastdb", "-in", fasta, "-dbtype", "nucl", "-out", f"{work}/db", "-logfile", f"{work}/makeblastdb.log"])
fmt = "6 qseqid sseqid pident length qlen qstart qend sstart send evalue bitscore"
tb = run([f"{BL}/tblastn", "-query", f"{refdir}/mito_proteins.faa", "-db", f"{work}/db", "-db_gencode", "4", "-evalue", "1e-10",
          "-outfmt", fmt, "-num_threads", str(threads), "-max_target_seqs", "1000", "-seg", "no"])
open(f"{out}/tblastn_hits.tsv", "w").write("qseqid\tsseqid\tpident\tlength\tqlen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore\n" + tb)
hits = [l.split("\t") for l in tb.strip().split("\n") if l]
cov = {}  # (contig, query) -> intervals
for h in hits:
    cov.setdefault((h[1], h[0]), []).append((int(h[5]) - 1, int(h[6]), int(h[4])))
fam_found = {}  # contig -> {family: best coverage}
prot_ids = {}
for (c, q), iv in cov.items():
    f = family(q)
    if f is None: continue
    qlen = iv[0][2]; frac = union_length([(a, b) for a, b, _ in iv]) / qlen
    if frac >= MIN_PROT_COV:
        fam_found.setdefault(c, {})
        fam_found[c][f] = max(fam_found[c].get(f, 0), round(frac, 3))
any_core_hit = {c for (c, q) in cov if family(q)}

# ---- 2. genome evidence
paf = run([f"{QC}/minimap2", "-x", "asm20", "-c", "-t", str(threads), fasta, f"{refdir}/mito_genomes.fasta"])
open(f"{out}/ref_genome_alignments.paf", "w").write(paf)
gen_iv = {}
for r in read_paf(f"{out}/ref_genome_alignments.paf"):
    gen_iv.setdefault(r["tname"], []).append((r["tstart"], r["tend"]))
gen_bp = {c: union_length(iv) for c, iv in gen_iv.items()}

# ---- 3. depth
D = os.environ.get("DEPTH_DIR", "")
have_depth = bool(D) and os.path.exists(f"{D}/depth.regions.bed.gz") and os.path.exists(f"{D}/depth.per_contig.tsv")
mean_depth, med_depth, nuc_med = {}, {}, float("nan")
if have_depth:
    win = read_window_depth(f"{D}/depth.regions.bed.gz")
    pc = pd.read_csv(f"{D}/depth.per_contig.tsv", sep="\t")
    mean_depth = dict(zip(pc.contig, pc.mean_depth))
    by = {}
    for c, s, e, d in win: by.setdefault(c, []).append(d)
    med_depth = {c: statistics.median(v) for c, v in by.items()}
    excl = set(fam_found) | set(gen_bp) | any_core_hit
    nuc_med = nuclear_median(win, excl)

reads_used = open(f"{D}/reads_used.txt").read().strip().split("/")[-1] if have_depth and os.path.exists(f"{D}/reads_used.txt") else None

# ---- classes
rows = []
for n in seqs:
    nf = len(fam_found.get(n, {})); gb = gen_bp.get(n, 0)
    ratio = mean_depth.get(n, 0.0) / nuc_med if have_depth and nuc_med else float("nan")
    if nf >= MIN_FAMILIES: cls = "mitochondrial"
    elif nf >= 1 or gb >= MIN_GENOME_BP:
        cls = ("candidate" if ratio >= MIN_RATIO else "nuclear_with_mito_like_hit") if have_depth else "candidate_no_depth"
    else: cls = "nuclear"
    rows.append(dict(contig=n, length=L[n], gc=round(GC[n], 4), core_families_found=nf, families=";".join(sorted(fam_found.get(n, {}))),
                     genome_aligned_bases=gb, mean_depth=mean_depth.get(n, 0.0), median_window_depth=med_depth.get(n, 0.0),
                     depth_ratio_to_nuclear_median=ratio, **{"class": cls}))
T = pd.DataFrame(rows)
evidence = T[(T["class"] != "nuclear") | (T.core_families_found > 0) | (T.genome_aligned_bases > 0) | (T.depth_ratio_to_nuclear_median >= 5)]
evidence.sort_values(["class", "length"], ascending=[True, False]).to_csv(f"{out}/contigs_with_evidence.tsv", sep="\t", index=False)
mt = T[T["class"] == "mitochondrial"].sort_values("length", ascending=False)

# ---- circularity of the contigs of class mitochondrial (and candidates)
def end_overlap(name):
    s = seqs[name]; n = len(s); k = min(n // 2, 20000)
    exact = 0
    for m in range(min(5000, n // 2), 29, -1):
        if s[:m].upper() == s[-m:].upper(): exact = m; break
    write_fasta(f"{work}/tail.fa", {"tail": s[-k:].upper()}); write_fasta(f"{work}/head.fa", {"head": s[:k].upper()})
    p = run([f"{QC}/minimap2", "-x", "asm5", "-c", "--cs", "-t", "1", f"{work}/tail.fa", f"{work}/head.fa"])
    open(f"{work}/ends.paf", "w").write(p)
    best = None
    for r in read_paf(f"{work}/ends.paf"):
        # the start of the head must align to the end of the tail, same strand
        if r["strand"] == "+" and r["qstart"] <= 50 and r["tend"] >= r["tlen"] - 50:
            if best is None or r["alnlen"] > best["alnlen"]: best = r
    return exact, (best["qend"] - best["qstart"] if best else 0), (best["nmatch"] / best["alnlen"] if best else float("nan"))
circ = {}
for n in list(T[T["class"].isin(["mitochondrial", "candidate", "candidate_no_depth"])].contig):
    circ[n] = end_overlap(n)

# ---- comparison with the mitochondrion record of NCBI
nc_path = ncbi_hw2_file(INPUT, "genomic.fna.gz")
rep = ncbi_hw2_file(INPUT, "assembly_report.txt")
macc = ncbi_hw2_mito_accession(rep)
ncm = need_record(read_fasta(nc_path), macc, nc_path)
write_fasta(f"{work}/ncbi_mito.fa", {macc: ncm.upper()})
cmp_rows, ncbi_cmp = [], {}
mt_names = list(mt.contig)
if mt_names:
    write_fasta(f"{work}/mito_contigs.fa", {n: seqs[n].upper() for n in mt_names})
    p = run([f"{QC}/minimap2", "-x", "asm5", "-c", "--cs", "-t", "1", f"{work}/ncbi_mito.fa", f"{work}/mito_contigs.fa"])
    open(f"{out}/ncbi_mito_alignments.paf", "w").write(p)
    pr = read_paf(f"{out}/ncbi_mito_alignments.paf")
    tot = dict(match=0, substitutions=0, inserted_bases=0, deleted_bases=0, insertion_events=0, deletion_events=0)
    for r in pr:
        for k, v in cs_counts(r["tags"].get("cs", "")).items(): tot[k] += v
    ref_cov = union_length([(r["tstart"], r["tend"]) for r in pr]) / len(ncm) if pr else 0.0
    qtot = sum(L[n] for n in mt_names)
    q_cov = sum(union_length([(r["qstart"], r["qend"]) for r in pr if r["qname"] == n]) for n in mt_names) / qtot
    aln_bases = sum(r["alnlen"] for r in pr); nm = sum(r["nmatch"] for r in pr)
    ncbi_cmp = dict(ncbi_record=macc, ncbi_length=len(ncm), alignments=len(pr), ncbi_record_coverage=round(ref_cov, 5),
                    assembly_mito_coverage=round(q_cov, 5), identity_of_aligned=round(nm / aln_bases, 5) if aln_bases else None, aligned_bases=aln_bases, **tot,
                    length_difference_assembly_minus_ncbi=qtot - len(ncm))
else:
    ncbi_cmp = dict(ncbi_record=macc, ncbi_length=len(ncm), alignments=0, note="no mitochondrial contig found")
    # still align the whole assembly to the record to say whether the sequence is present in pieces
# alignment of the NCBI record to the whole assembly (shows whether it is found anywhere)
p = run([f"{QC}/minimap2", "-x", "asm5", "-c", "-t", str(threads), fasta, f"{work}/ncbi_mito.fa"])
open(f"{out}/ncbi_mito_vs_assembly.paf", "w").write(p)
pr = read_paf(f"{out}/ncbi_mito_vs_assembly.paf")
ncbi_cmp["ncbi_record_covered_by_whole_assembly"] = round(union_length([(r["qstart"], r["qend"]) for r in pr]) / len(ncm), 5) if pr else 0.0
ncbi_cmp["ncbi_record_best_contig"] = max(pr, key=lambda r: r["alnlen"])["tname"] if pr else None

# ---- per-contig table and summary
mt = mt.copy()
for col, i in (("end_overlap_exact_bases", 0), ("end_overlap_aligned_bases", 1), ("end_overlap_identity", 2)):
    mt[col] = [circ[n][i] for n in mt.contig]
mt["circular_by_end_overlap"] = (mt.end_overlap_exact_bases >= 30) | ((mt.end_overlap_aligned_bases >= 100) & (mt.end_overlap_identity >= 0.9))
mt["circular_genome_length_estimate"] = [int(l - o) if c else None for l, o, c in zip(mt.length, mt.end_overlap_aligned_bases, mt.circular_by_end_overlap)]   # contig length minus the duplicated ends
mt.to_csv(f"{out}/mito_contigs.tsv", sep="\t", index=False)
cand = T[T["class"].isin(["candidate", "candidate_no_depth"])].copy()
for col, i in (("end_overlap_exact_bases", 0), ("end_overlap_aligned_bases", 1)):
    cand[col] = [circ[n][i] for n in cand.contig]
cand.to_csv(f"{out}/candidate_contigs.tsv", sep="\t", index=False)

def n50(lengths):
    s = sorted(lengths, reverse=True); h = sum(s) / 2; c = 0
    for x in s:
        c += x
        if c >= h: return x
mito_set = set(mt.contig)
nuc_lengths = [L[n] for n in L if n not in mito_set]
nuc_gc = sum(GC[n] * L[n] for n in L if n not in mito_set) / sum(nuc_lengths)
summary = dict(assembly=asm, fasta=os.path.basename(fasta), contigs=len(L), total_length=sum(L.values()), n50=n50(L.values()),
               mitochondrial_contigs=len(mt), mitochondrial_length=int(mt.length.sum()) if len(mt) else 0,
               mitochondrial_contig_names=list(mt.contig), mitochondrial_pieces=len(mt),
               candidate_contigs=int(len(cand)), candidate_names=list(cand.contig),
               core_families_found_union=sorted({f for n in mito_set for f in fam_found.get(n, {})}),
               core_families_found_union_count=len({f for n in mito_set for f in fam_found.get(n, {})}),
               circular_by_end_overlap=[bool(x) for x in mt.circular_by_end_overlap] if len(mt) else [],
               end_overlap_aligned_bases=[int(x) for x in mt.end_overlap_aligned_bases] if len(mt) else [],
               end_overlap_exact_bases=[int(x) for x in mt.end_overlap_exact_bases] if len(mt) else [],
               circular_genome_length_estimate=[(None if (x is None or x != x) else int(x)) for x in mt.circular_genome_length_estimate] if len(mt) else [],
               gc_mitochondrial=[float(x) for x in mt.gc] if len(mt) else [], gc_nuclear_length_weighted=round(nuc_gc, 4),
               depth_available=have_depth, depth_reads_file=reads_used, nuclear_median_window_depth=nuc_med if have_depth else None,
               mean_depth_mitochondrial=[float(x) for x in mt.mean_depth] if len(mt) else [],
               depth_ratio_mitochondrial=[float(x) for x in mt.depth_ratio_to_nuclear_median] if len(mt) else [],
               nuclear_length_without_mitochondrial=sum(nuc_lengths), nuclear_contigs_without_mitochondrial=len(nuc_lengths),
               n50_without_mitochondrial=n50(nuc_lengths), comparison_with_ncbi_mitochondrion=ncbi_cmp,
               reference_genomes=[l.split("\t")[0] for l in open(f"{refdir}/mito_refs.tsv").read().splitlines()[1:]],
               thresholds=dict(min_core_families=MIN_FAMILIES, min_protein_coverage=MIN_PROT_COV, min_genome_bases=MIN_GENOME_BP, min_depth_ratio=MIN_RATIO))
if len(mt):   # scalar copies of the values of the longest mitochondrial contig (for quoting in documents)
    t0 = mt.iloc[0]
    summary.update(longest_mito_contig=t0.contig, longest_mito_length=int(t0.length), longest_mito_gc=float(t0.gc), longest_mito_circular=bool(t0.circular_by_end_overlap),
                   longest_mito_end_overlap_aligned_bases=int(t0.end_overlap_aligned_bases), longest_mito_end_overlap_exact_bases=int(t0.end_overlap_exact_bases),
                   longest_mito_circle_length_estimate=(None if (t0.circular_genome_length_estimate is None or t0.circular_genome_length_estimate != t0.circular_genome_length_estimate) else int(t0.circular_genome_length_estimate)),
                   longest_mito_mean_depth=float(t0.mean_depth), longest_mito_depth_ratio=float(t0.depth_ratio_to_nuclear_median))
json.dump(summary, open(f"{out}/summary.json", "w"), indent=1, default=lambda x: None if x != x else str(x))
print(json.dumps(summary, indent=1, default=str))
