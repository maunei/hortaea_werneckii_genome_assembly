#!/bin/bash
#SBATCH --job-name=hw_04_control_flye
#SBATCH --account=<ACCOUNT>
#SBATCH --time=08:00:00
#SBATCH --mem=140G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 04_control_flye

# Step 04 (control): Flye with its default settings on the same filtered reads and the same genome size.
READS=${READS:-$WORK/reads/pacbio/filtered_clean.fastq}; OUT="$WORK/asm/ctrl_flye"; R="$RESULTS/04_procedure/ctrl_flye"; mkdir -p "$OUT" "$R"
export PATH="$MODERN_BIN:$QC_BIN:$PATH"
flye --version
/usr/bin/time -v flye --pacbio-raw "$READS" --genome-size 50m --out-dir "$OUT/flye" --threads 16 > "$LOGDIR/flye.out" 2> "$LOGDIR/flye.time"; rc=$?; echo "flye exit $rc"
[ $rc = 0 ] || exit 3
cp "$OUT/flye/assembly.fasta" "$OUT/final.fasta"; seqkit stats -a -T "$OUT/final.fasta" > "$R/assembly_stats.tsv"; cut -f1-9,13,14 "$R/assembly_stats.tsv"
grep -hE "Elapsed|Maximum resident" "$LOGDIR/flye.time" > "$R/time_memory.txt"
hw_end 04_control_flye
