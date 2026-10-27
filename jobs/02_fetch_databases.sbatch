#!/bin/bash
#SBATCH --job-name=hw_fetch_databases
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start fetch_databases
# The reference data are downloaded once and used offline afterwards.
#   1. BUSCO lineage fungi_odb10 and Swiss-Prot fungal proteins (evaluation 2)
#   2. reference collection of the contaminant screen (step 05): about 83 GB written, about 30 minutes with 4 parallel downloads
# Both scripts can be run again: finished downloads are kept, and every set is recorded with source, version and checksum in envs/databases.tsv.
bash "$HW/scripts/06_fetch_databases.sh"
FETCH_JOBS=4 bash "$HW/scripts/fetch_screen_databases.sh"
hw_end fetch_databases
