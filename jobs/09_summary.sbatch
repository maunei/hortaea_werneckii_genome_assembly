#!/bin/bash
#SBATCH --job-name=hw_09_summary
#SBATCH --account=<ACCOUNT>
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 09_summary

# Step 09 (last job of scripts/submit_all.sh): summary tables, figures and the assessment of every evaluation; checksums of the three runs; time and memory of the jobs;
# the released assembly; the check of the results against the expected table (step 10). Needs the results of all earlier steps.
export HW RESULTS
"$PY" "$HW/scripts/09_summary.py" || exit 2
"$PY" "$HW/scripts/09_qc_figures.py" || exit 3
"$PY" "$HW/scripts/09_workflow_figure.py" || exit 3
bash "$HW/scripts/09_replicates.sh" || exit 3
"$PY" "$HW/scripts/09_release.py" proc_r1 || exit 4
"$PY" "$HW/scripts/09_resources.py" || echo "resources table not made (job accounting not available)"
"$PY" "$HW/scripts/10_validate.py" check "$RESULTS" || echo "validation reported differences; see results/10_validation/validation_report.txt"
hw_end 09_summary
