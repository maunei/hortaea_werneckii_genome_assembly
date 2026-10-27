#!/bin/bash
#SBATCH --job-name=hw_04_control_canu
#SBATCH --account=<ACCOUNT>
#SBATCH --time=12:00:00
#SBATCH --mem=150G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 04_control_canu

# Step 04 (control): Canu with its default settings and its own read correction, on the same filtered reads and the same genome size.
READS=${READS:-$WORK/reads/pacbio/filtered_clean.fastq}; OUT="$WORK/asm/ctrl_canu"; R="$RESULTS/04_procedure/ctrl_canu"; mkdir -p "$OUT" "$R"
export PATH="$MODERN_BIN:$QC_BIN:$PATH"
/usr/bin/time -v canu -p canu -d "$OUT/canu" genomeSize=50m -pacbio "$READS" useGrid=false maxThreads=16 maxMemory=140 stopOnLowCoverage=3 > "$LOGDIR/canu.out" 2> "$LOGDIR/canu.time"; rc=$?; echo "canu exit $rc"
[ $rc = 0 ] || exit 3
cp "$OUT/canu/canu.contigs.fasta" "$OUT/final.fasta"; seqkit stats -a -T "$OUT/final.fasta" > "$R/assembly_stats.tsv"; cut -f1-9,13,14 "$R/assembly_stats.tsv"
grep -hE "Elapsed|Maximum resident" "$LOGDIR/canu.time" > "$R/time_memory.txt"
hw_end 04_control_canu
