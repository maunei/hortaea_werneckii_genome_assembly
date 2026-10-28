#!/bin/bash
#SBATCH --job-name=hw_mito
#SBATCH --account=<ACCOUNT>
#SBATCH --time=04:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start mito
# Step 07c: mitochondrial genome of one assembly.
# Parameters (sbatch --export=ALL,ASM=...,FASTA=...): ASM = assembly name; FASTA = assembly FASTA (default $WORK/asm/$ASM/final.fasta);
# READS = PacBio reads for the depth (default $WORK/reads/pacbio/hq_clean.fastq; without reads the depth is skipped and reported as unavailable);
# OUT_NAME = output sub-folder (default ASM).
: "${ASM:?set ASM}"; FASTA="${FASTA:-$WORK/asm/$ASM/final.fasta}"; READS="${READS:-$WORK/reads/pacbio/hq_clean.fastq}"; OUT_NAME="${OUT_NAME:-$ASM}"
THREADS="${SLURM_CPUS_PER_TASK:-8}"
OUT="$RESULTS/07_comparator/mito/$OUT_NAME"; TMP="$WORK/07_comparator/mito_$OUT_NAME"; mkdir -p "$OUT" "$TMP"
[ -s "$DBS/mito_refs/mito_genomes.fasta" ] || bash "$HW/scripts/07_fetch_mito_refs.sh"     # reference mitochondrial genomes and proteins (RefSeq)
export DEPTH_DIR="${DEPTH_DIR:-$WORK/07_comparator/$OUT_NAME}"
if [ -s "$READS" ] || [ -s "$DEPTH_DIR/depth.per_contig.tsv" ]; then
  bash "$HW/scripts/07_depth.sh" "$OUT_NAME" "$FASTA" "$READS" "$THREADS" || { echo "depth failed" >&2; exit 1; }
else
  echo "reads not found ($READS): the depth is skipped"; unset DEPTH_DIR
fi
"$PY" "$HW/scripts/07_mito.py" "$ASM" "$FASTA" "$OUT" "$TMP" "$THREADS" || exit 4
hw_end mito
