#!/bin/bash
#SBATCH --job-name=hw_01_software
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 01_software
# Step 1: the ten software environments are made from the lock files in envs/lockfiles (about 2 h 15 min, about 304,000 files, 15 GB).
# Needs micromamba or conda on the path of the person who submits the job (the path is passed on to the job). A stopped job can be submitted again:
# environments that are complete are kept, incomplete ones are made again.
mkdir -p "$HW/logs"
bash "$HW/scripts/make_environments.sh" 2>&1 | tee "$HW/logs/make_environments.txt"
grep -q "FAILED\|not found" "$HW/logs/make_environments.txt" && { echo "an environment could not be created (see above)" >&2; exit 3; }
CHECK=1 bash "$HW/scripts/make_environments.sh" || exit 4
hw_end 01_software
