#!/bin/bash
#SBATCH --job-name=hw_08_shared_differences
#SBATCH --account=<ACCOUNT>
#SBATCH --time=00:30:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=1
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 08_shared_differences
set -euo pipefail

# Step 08, second part: differences from the Illumina reads that are at the same place in two assemblies.
# Usage (from the package folder, after jobs/08_illumina_accuracy.sbatch has run for both assemblies):
#   sbatch --export=ALL,ASM_A=proc_r1,ASM_B=hw2 jobs/08_shared_differences.sbatch
# Parameters: ASM_A, ASM_B (assembly names). Optional: FASTA_A, FASTA_B (default $WORK/asm/<ASM>/final.fasta), DIFF_A, DIFF_B
# (default $RESULTS/08_illumina_accuracy/<ASM>/differences.tsv), OUTDIR (default $RESULTS/08_illumina_accuracy/shared/<ASM_A>_vs_<ASM_B>), FLANK (20).
: "${ASM_A:?set ASM_A}"; : "${ASM_B:?set ASM_B}"
FASTA_A="${FASTA_A:-$WORK/asm/$ASM_A/final.fasta}"; FASTA_B="${FASTA_B:-$WORK/asm/$ASM_B/final.fasta}"
DIFF_A="${DIFF_A:-$RESULTS/08_illumina_accuracy/$ASM_A/differences.tsv}"; DIFF_B="${DIFF_B:-$RESULTS/08_illumina_accuracy/$ASM_B/differences.tsv}"
OUTDIR="${OUTDIR:-$RESULTS/08_illumina_accuracy/shared/${ASM_A}_vs_${ASM_B}}"
for f in "$FASTA_A" "$FASTA_B" "$DIFF_A" "$DIFF_B"; do [ -s "$f" ] || { echo "ERROR: missing or empty $f" >&2; exit 1; }; done
"$PY" "$HW/scripts/shared_differences.py" --diff-a "$DIFF_A" --fasta-a "$FASTA_A" --name-a "$ASM_A" \
  --diff-b "$DIFF_B" --fasta-b "$FASTA_B" --name-b "$ASM_B" --flank "${FLANK:-20}" --outdir "$OUTDIR"
hw_end 08_shared_differences
