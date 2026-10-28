#!/bin/bash
#SBATCH --job-name=hw_genbank_files
#SBATCH --account=<ACCOUNT>
#SBATCH --time=00:30:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start genbank_files
# Step 07a: comparison of the complete GitHub file of Hw 2.0 with the other GenBank files of the repository and the NCBI record.
OUT="$RESULTS/07_comparator/genbank_files"; TMP="$WORK/07_comparator/genbank_files"; mkdir -p "$OUT" "$TMP"
"$PY" "$HW/scripts/07_genbank_files.py" "$OUT" "$TMP" "$QC_BIN/minimap2"
hw_end genbank_files
