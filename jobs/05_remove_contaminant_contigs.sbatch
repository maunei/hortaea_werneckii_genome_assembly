#!/bin/bash
#SBATCH --job-name=hw_05_remove_contigs
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=96G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 05_remove_contigs

# Step 05c: contaminant screen of the polished contigs (the screen of step 02b applied to contigs) and removal of the contigs that it excludes: a contig is excluded when alignments to
# contaminant sequence (bacteria, archaea, viruses, human, cloning vectors) cover at least half of it and no alignment to fungal sequence passes the filter. No base is edited.
# Parameter (sbatch --export=ALL,OUTNAME=...): OUTNAME = name of the assembly (for example proc_r1); input $WORK/asm/$OUTNAME/polished.fasta, output $WORK/asm/$OUTNAME/final.fasta.
OUTNAME=${OUTNAME:?set OUTNAME}; IN="$WORK/asm/$OUTNAME/polished.fasta"; OUT="$WORK/asm/$OUTNAME/final.fasta"; R="$RESULTS/05_polish/$OUTNAME"; mkdir -p "$R"
[ -s "$IN" ] || { echo "no polished assembly $IN (run jobs/05_polish.sbatch)"; exit 2; }
SCR="${OUTNAME}_polished"
ASM="$SCR" FASTA="$IN" THREADS="${SLURM_CPUS_PER_TASK:-16}" bash "$HW/scripts/screen_contigs.sh" || exit 3
D="$RESULTS/02_pacbio_reads/screen_contigs/$SCR"
"$PY" - <<PYEOF || exit 4
import gzip, csv
excl = {l.strip() for l in open("$D/${SCR}_excluded_contigs.txt") if l.strip()}
per = {r["contig"]: r for r in csv.DictReader(gzip.open("$D/${SCR}_per_contig.tsv.gz", "rt"), delimiter="\t")}
n = k = 0; keep = True
with open("$IN") as f, open("$OUT.tmp", "w") as w:
    for l in f:
        if l[0] == ">":
            n += 1; keep = l[1:].split()[0] not in excl; k += keep
        if keep: w.write(l)
with open("$R/removed_contigs.tsv", "w") as w:
    w.write("contig\tlength\tbest_contaminant\tclass\n")
    for c in sorted(excl): w.write(f"{c}\t{per[c]['length']}\t{per[c]['best_contaminant_organism']}\t{per[c]['class']}\n")
print(n, "contigs before,", k, "after; removed:", sorted(excl))
PYEOF
mv "$OUT.tmp" "$OUT"
"$QC_BIN/seqkit" stats -a -T "$IN" "$OUT" > "$R/assembly_stats_after_removal.tsv"; cut -f1-9,13,14 "$R/assembly_stats_after_removal.tsv"
hw_end 05_remove_contigs
