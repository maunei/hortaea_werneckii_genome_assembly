#!/usr/bin/env python
"""Step 07a: compare the complete GitHub file Hw2.fasta.gz with the other copies of Hw 2.0 (GenBank folder of the repository and the NCBI record).
Usage: 07_genbank_files.py OUTDIR WORKDIR MM2   (locations of the inputs are read from the environment variable INPUT set by config/config.sh)
Writes: contigs_by_file.tsv, file_summary.tsv, differing_sequences.tsv, only_in_one_file.tsv, the22_ids.tsv, summary.json."""
import json, os, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw07_common import *

out, work, mm2 = sys.argv[1:4]
os.makedirs(out, exist_ok=True); os.makedirs(work, exist_ok=True)
INPUT = os.environ["INPUT"]
GH = f"{INPUT}/hw2/github_Hortaea_werneckii"
NC = ncbi_hw2_file(INPUT, "genomic.fna.gz")
REP = ncbi_hw2_file(INPUT, "assembly_report.txt")
files = {  # label -> (path, description)
    "github_Hw2.fasta.gz": (f"{GH}/assemblies/Hw2/Hw2.fasta.gz", "complete file of the assemblies folder (comparator of the package)"),
    "genbank_Hw2.fasta": (f"{GH}/annotation/GenBank/Hw2.fasta", "file of the GenBank folder (a soft link to ../../assemblies/Hw2/Hw2.fasta)"),
    "genbank_Hw2.MTedit.fasta": (f"{GH}/annotation/GenBank/Hw2.MTedit.fasta", "same file with the mitochondrial contig renamed"),
    "genbank_annotated1": (f"{GH}/annotation/GenBank/annotated1/genome.fasta", "genome file of the annotation folder annotated1"),
    "genbank_fixed1": (f"{GH}/annotation/GenBank/fixed1/genome.fasta", "genome file of the annotation folder fixed1"),
    "ncbi_GCA_002127715.1": (NC, "NCBI record (contig names are accessions; mapped to unitig names with the assembly report)"),
}
# accession -> unitig name from the assembly report of NCBI
acc2name, mito_acc = {}, None
for line in open(REP, newline=None):
    if line.startswith("#"): continue
    p = line.rstrip("\r\n").split("\t")
    acc2name[p[4]] = p[0]
    if p[7] == "non-nuclear": mito_acc = p[4]

seqs, status = {}, {}
for lab, (path, desc) in files.items():
    if os.path.exists(path):  # os.path.exists is False for a broken soft link
        seqs[lab] = read_fasta(path); status[lab] = "read"
    else:
        status[lab] = "absent" + (" (broken soft link)" if os.path.islink(path) else "")
gh = seqs["github_Hw2.fasta.gz"]
# rename NCBI accessions to unitig names for comparison
ncbi_raw = seqs["ncbi_GCA_002127715.1"]
need_record(ncbi_raw, mito_acc, NC)   # stops with a clear message when the wrong file was read
seqs["ncbi_GCA_002127715.1"] = {acc2name.get(k, k): v for k, v in ncbi_raw.items()}

# ---- per-contig table
rows, allnames = [], []
for lab, d in seqs.items():
    for n in d:
        if n not in allnames: allnames.append(n)
with open(f"{out}/contigs_by_file.tsv", "w") as o:
    labs = list(seqs)
    o.write("contig\t" + "\t".join(f"{l}:length\t{l}:md5\t{l}:md5_uppercase" for l in labs) + "\n")
    for n in allnames:
        cells = []
        for l in labs:
            s = seqs[l].get(n)
            cells += [str(len(s)), md5(s), md5(s.upper())] if s is not None else ["NA", "NA", "NA"]
        o.write(n + "\t" + "\t".join(cells) + "\n")

# ---- file-level comparison with the GitHub file
fs, differing, only = [], [], []
gh_md5 = {n: md5(s) for n, s in gh.items()}; gh_md5u = {n: md5(s.upper()) for n, s in gh.items()}
for lab, d in seqs.items():
    common = [n for n in d if n in gh]
    ident = [n for n in common if md5(d[n]) == gh_md5[n]]
    ident_u = [n for n in common if md5(d[n].upper()) == gh_md5u[n]]
    fs.append(dict(file=lab, status="read", contigs=len(d), total_bases=sum(map(len, d.values())),
                   names_in_common_with_github=len(common), identical_sequence=len(ident),
                   identical_ignoring_case=len(ident_u), only_in_github=len([n for n in gh if n not in d]),
                   only_in_this_file=len([n for n in d if n not in gh])))
    for n in common:
        if md5(d[n].upper()) != gh_md5u[n]: differing.append((lab, n, n))   # different bases (letter case is reported separately)
    for n in d:
        if n not in gh: only.append((lab, n))
    for n in gh:
        if n not in d and lab != "github_Hw2.fasta.gz": only.append(("missing_from:" + lab, n))
for lab, st in status.items():
    if st != "read": fs.append(dict(file=lab, status=st))
import pandas as pd
pd.DataFrame(fs).convert_dtypes().to_csv(f"{out}/file_summary.tsv", sep="\t", index=False)

# ---- sequences present under a different name in another file: find by identical md5 (or best alignment when none)
by_md5 = {}
for n, s in gh.items(): by_md5.setdefault(md5(s.upper()), []).append(n)
renamed = []
for lab, n in only:
    if lab.startswith("missing_from:"): continue
    s = seqs[lab][n]; hit = by_md5.get(md5(s.upper()), [])
    renamed.append(dict(file=lab, contig=n, length=len(s), identical_to_github_contig=";".join(hit) if hit else "none"))
pd.DataFrame(renamed, columns=["file", "contig", "length", "identical_to_github_contig"]).to_csv(f"{out}/only_in_one_file.tsv", sep="\t", index=False)

# ---- alignment of the sequences that differ (same name, different bases; letter case is ignored here and reported in case_differences.tsv)
res = []
for lab, n, _ in differing:
    a, b = gh[n], seqs[lab][n]
    write_fasta(f"{work}/ref.fa", {n: a.upper()}); write_fasta(f"{work}/qry.fa", {n: b.upper()})
    out_paf = run([mm2, "-x", "asm5", "-c", "--cs", "-t", "1", f"{work}/ref.fa", f"{work}/qry.fa"])
    open(f"{work}/d.paf", "w").write(out_paf)
    paf = read_paf(f"{work}/d.paf")
    tot = dict(match=0, substitutions=0, inserted_bases=0, deleted_bases=0, insertion_events=0, deletion_events=0)
    for r in paf:
        for k, v in cs_counts(r["tags"].get("cs", "")).items(): tot[k] += v
    qcov = union_length([(r["qstart"], r["qend"]) for r in paf]) / len(b) if paf else 0
    res.append(dict(file=lab, contig=n, length_github=len(a), length_other=len(b), alignments=len(paf), query_coverage=round(qcov, 6), **tot,
                    same_ignoring_case=a.upper() == b.upper(), mitochondrial=(n == "unitig_320")))
DIFFCOLS = ["file", "contig", "length_github", "length_other", "alignments", "query_coverage", "match", "substitutions", "inserted_bases", "deleted_bases", "insertion_events", "deletion_events", "same_ignoring_case", "mitochondrial"]
pd.DataFrame(res, columns=DIFFCOLS).to_csv(f"{out}/differing_sequences.tsv", sep="\t", index=False)   # header only when no sequence differs

# ---- case differences in the NCBI record versus the GitHub file (soft-masked bases)
case_rows = []
for lab, d in seqs.items():
    if lab == "github_Hw2.fasta.gz": continue
    nd = [n for n in d if n in gh and d[n] != gh[n] and d[n].upper() == gh[n].upper()]
    case_rows.append(dict(file=lab, contigs_differing_only_in_case=len(nd), differing_contigs_in_list=";".join(nd[:5])))
pd.DataFrame(case_rows).to_csv(f"{out}/case_differences.tsv", sep="\t", index=False)

# ---- the sequences of the GitHub file that are absent from the NCBI record
nc = seqs["ncbi_GCA_002127715.1"]
nc_md5u = {md5(s.upper()): n for n, s in nc.items()}
t22 = []
for n, s in gh.items():
    in_by_name, in_by_md5 = n in nc, md5(s.upper()) in nc_md5u
    if not in_by_name and not in_by_md5:
        t22.append(dict(contig=n, length=len(s), gc=round(gc_fraction(s), 5), md5=md5(s), md5_uppercase=md5(s.upper())))
t22 = pd.DataFrame(t22).sort_values("length", ascending=False)
t22.to_csv(f"{out}/the22_ids.tsv", sep="\t", index=False)
nonn = [n for n in nc if n not in gh]
short = {"github_Hw2.fasta.gz": "github", "genbank_Hw2.MTedit.fasta": "mtedit", "genbank_annotated1": "annotated1", "genbank_fixed1": "fixed1", "ncbi_GCA_002127715.1": "ncbi", "genbank_Hw2.fasta": "genbank_hw2"}
by_file = {short[r["file"]]: {k: v for k, v in r.items() if k != "file"} for r in fs}
summary = dict(by_file=by_file, github_contigs=len(gh), github_bases=sum(map(len, gh.values())), ncbi_contigs=len(nc), ncbi_bases=sum(map(len, nc.values())),
               ncbi_contigs_with_identical_sequence_in_github=sum(1 for n in nc if n in gh and nc[n].upper() == gh[n].upper()),
               ncbi_contigs_with_identical_sequence_including_case=sum(1 for n in nc if n in gh and nc[n] == gh[n]),
               ncbi_mito_accession=mito_acc, ncbi_mito_unitig=acc2name.get(mito_acc), ncbi_mito_length=len(ncbi_raw[mito_acc]),
               ncbi_names_not_in_github=len(nonn), absent_from_ncbi=len(t22), absent_from_ncbi_total_bases=int(t22.length.sum()),
               absent_from_ncbi_min_length=int(t22.length.min()), absent_from_ncbi_max_length=int(t22.length.max()),
               file_status=status, files_with_other_name_for_a_contig=renamed, differing_sequences=res)
json.dump(summary, open(f"{out}/summary.json", "w"), indent=1, default=str)
print(pd.DataFrame(fs).to_string()); print(pd.DataFrame(renamed).to_string()); print(pd.DataFrame(res).to_string()); print(pd.DataFrame(case_rows).to_string()); print(len(t22))
