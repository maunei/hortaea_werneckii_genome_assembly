#!/bin/bash
#SBATCH --job-name=hw_screen_contigs
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=96G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start screen_contigs
# Contaminant screen of the contigs of one assembly. Parameters: ASM (name) and FASTA (path); example:
#   sbatch --export=ALL,ASM=hw2,FASTA=$WORK/asm/hw2/final.fasta jobs/02_screen_contigs.sbatch
: "${ASM:?set ASM}"; : "${FASTA:?set FASTA}"
bash "$HW/scripts/screen_contigs.sh" || exit 4
hw_end screen_contigs
