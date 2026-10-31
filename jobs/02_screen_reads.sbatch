#!/bin/bash
#SBATCH --job-name=hw_screen_reads
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start screen_reads
# Contaminant screen of hq_subreads.fastq and filtered_subreads.fastq; writes hq_clean.fastq, filtered_clean.fastq and the marker READY_02.
# Needs the databases (scripts/fetch_screen_databases.sh, jobs/02_screen_db_index.sbatch) and the marker READY_02A of the read-set step.
export REQUIRE_MARKER="${REQUIRE_MARKER-$WORK/reads/pacbio/READY_02A}"
bash "$HW/scripts/screen_reads.sh" || exit 4
hw_end screen_reads
