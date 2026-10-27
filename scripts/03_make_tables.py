#!/usr/bin/env python3
"""Step 03: build results/03_rna_illumina/read_counts.tsv and qc_summary.tsv from the conversion counts, the fastp json files and the FastQC data files.
Usage: 03_make_tables.py WORK_READS_PARENT QCDIR OUTDIR RUN:GROUP [RUN:GROUP ...]
Only the standard library is used."""
import csv, json, os, re, sys, zipfile

reads_parent, qcdir, outdir = sys.argv[1:4]
runs = [a.split(":") for a in sys.argv[4:]]
os.makedirs(outdir, exist_ok=True)

# ---- read_counts.tsv
with open(os.path.join(outdir, "read_counts.tsv"), "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["run", "pairs_archive_record", "pairs_found_mate1", "pairs_found_mate2", "reads_without_mate", "read_names_match", "status"])
    for run, group in runs:
        with open(os.path.join(reads_parent, group, run + ".counts.tsv")) as f:
            w.writerow(f.read().rstrip("\n").split("\t"))

def fastqc_module(zpath, module):
    """Lines of one module of the FastQC data file inside the zip archive."""
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.endswith("fastqc_data.txt")][0]
        text = z.read(name).decode()
    block = re.search(r">>%s\t.*?\n(.*?)>>END_MODULE" % re.escape(module), text, re.S)
    return [l.split("\t") for l in block.group(1).splitlines() if l and not l.startswith("#")] if block else []

def mean_quality(zpath):
    rows = fastqc_module(zpath, "Per sequence quality scores")
    n = sum(float(c) for _, c in rows)
    return sum(float(q) * float(c) for q, c in rows) / n

def adapter_max(zpath):
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.endswith("fastqc_data.txt")][0]
        text = z.read(name).decode()
    block = re.search(r">>Adapter Content\t.*?\n(.*?)>>END_MODULE", text, re.S)
    best = 0.0
    for l in block.group(1).splitlines():
        if l.startswith("#") or not l.strip():
            continue
        best = max([best] + [float(x) for x in l.split("\t")[1:]])
    return best

cols = ["run", "pairs", "read_length_mate1", "read_length_mate2", "mean_quality_mate1_fastqc", "mean_quality_mate2_fastqc",
        "percent_bases_q30_fastp", "percent_bases_q20_fastp", "adapter_trimmed_reads_percent_fastp", "adapter_max_percent_mate1_fastqc",
        "adapter_max_percent_mate2_fastqc", "duplication_percent_fastp", "gc_percent_fastp", "insert_size_peak_fastp",
        "insert_size_unknown_percent_fastp", "fastqc_failed_modules_mate1", "fastqc_failed_modules_mate2"]
def total_sequences(zpath):
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.endswith("fastqc_data.txt")][0]
        text = z.read(name).decode()
    return int(re.search(r"Total Sequences\t(\d+)", text).group(1))

def failed(zpath):
    with zipfile.ZipFile(zpath) as z:
        name = [n for n in z.namelist() if n.endswith("summary.txt")][0]
        lines = z.read(name).decode().splitlines()
    return ";".join(l.split("\t")[1] for l in lines if l.startswith("FAIL")) or "none"

with open(os.path.join(outdir, "qc_summary.tsv"), "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(cols)
    for run, group in runs:
        j = json.load(open(os.path.join(qcdir, "fastp", run + ".json")))
        s = j["summary"]["before_filtering"]
        pairs = j["read1_before_filtering"]["total_reads"]
        z1 = os.path.join(qcdir, "fastqc", run + "_1_fastqc.zip"); z2 = os.path.join(qcdir, "fastqc", run + "_2_fastqc.zip")
        for z in (z1, z2):  # every read of both files must have been seen by FastQC and by fastp
            if total_sequences(z) != pairs:
                sys.exit("FastQC total sequences differ from fastp pairs for " + z)
        ins = j["insert_size"]
        tot_reads = s["total_reads"]
        w.writerow([run, pairs, s["read1_mean_length"], s["read2_mean_length"],
                    "%.2f" % mean_quality(z1), "%.2f" % mean_quality(z2),
                    "%.2f" % (100 * s["q30_rate"]), "%.2f" % (100 * s["q20_rate"]),
                    "%.3f" % (100 * j["adapter_cutting"].get("adapter_trimmed_reads", 0) / tot_reads),
                    "%.3f" % adapter_max(z1), "%.3f" % adapter_max(z2),
                    "%.2f" % (100 * j["duplication"]["rate"]), "%.2f" % (100 * s["gc_content"]),
                    ins["peak"], "%.2f" % (100 * ins["unknown"] / pairs), failed(z1), failed(z2)])
print("tables written to", outdir)
