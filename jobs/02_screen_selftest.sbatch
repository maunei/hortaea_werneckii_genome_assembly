#!/bin/bash
#SBATCH --job-name=hw_screen_selftest
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=96G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start screen_selftest
# Self-test with simulated control reads mixed into a sample of real reads (see scripts/screen_selftest.sh).
# Run scripts/fetch_screen_test_genomes.sh first (needs internet).
bash "$HW/scripts/screen_selftest.sh" || exit 4
hw_end screen_selftest
