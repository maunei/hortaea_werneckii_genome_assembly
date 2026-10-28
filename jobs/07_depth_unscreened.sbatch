#!/bin/bash
#SBATCH --job-name=hw_07_depth_unscreened
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start depth_unscreened
# Step 07b (side table): PacBio depth of the 22 sequences of Hw 2.0 with the high-quality subreads BEFORE the contaminant screen, next to the depth with the screened reads,
# so that the effect of the screen on sequences of vector origin can be read. Needs the output of jobs/07_the22.sbatch.
D="$WORK/07_comparator/hw2_unscreened"; mkdir -p "$D"
DEPTH_DIR="$D" bash "$HW/scripts/07_depth.sh" hw2 "$WORK/asm/hw2/final.fasta" "$WORK/reads/pacbio/hq_subreads.fastq" "${SLURM_CPUS_PER_TASK:-16}" || exit 1
"$PY" - <<PYEOF
import csv
ids = [l.split("\t")[0] for l in open("$RESULTS/07_comparator/genbank_files/the22_ids.tsv").read().splitlines()[1:]]
def load(p): return {r["contig"]: r for r in csv.DictReader(open(p), delimiter="\t")}
a = load("$D/depth.per_contig.tsv"); b = load("$WORK/07_comparator/hw2/depth.per_contig.tsv")
med_a = sorted(float(r["mean_depth"]) for r in a.values())[len(a) // 2]
with open("$RESULTS/07_comparator/the22/depth_unscreened_and_screened_reads.tsv", "w") as w:
    w.write("sequence\tlength\tmean_depth_unscreened_reads\tmean_depth_screened_reads\n")
    for i in ids: w.write(f"{i}\t{a[i]['length']}\t{a[i]['mean_depth']}\t{b[i]['mean_depth']}\n")
PYEOF
hw_end depth_unscreened
