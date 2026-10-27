#!/bin/bash
#SBATCH --job-name=hw_02_compare_deposited
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=24G
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 02_compare_deposited

# Step 02a (check): the filtered subreads made here are compared with the FASTQ file that the authors deposited (run SRR5086624).
mkdir -p "$INPUT/pacbio_deposited"
"$PY" "$HW/scripts/fetch_archive.py" "$INPUT/manifests/pacbio_deposited_fastq.tsv" "$INPUT/pacbio_deposited" 4 || exit 2
"$PY" "$HW/scripts/compare_deposited_fastq.py" "$WORK/reads/pacbio/filtered_subreads.fastq" "$INPUT/pacbio_deposited/SRR5086624/Hw_PacBio.filtered_subreads.fastq.bz2" "$RESULTS/02_pacbio_reads/deposited_fastq_comparison.json" || exit 3
hw_end 02_compare_deposited
