#!/bin/bash
#SBATCH --job-name=hw_09_summary
#SBATCH --account=<ACCOUNT>
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 09_summary

# Step 09 (last job of scripts/submit_all.sh): summary tables, figures and the assessment of every evaluation; checksums of the three runs; time and memory of the jobs;
# the released assembly; the comparison of the results with the first analysis (step 10). Needs the results of all earlier steps.
export HW RESULTS
"$PY" "$HW/scripts/09_summary.py" || exit 2
rc=0   # the parts below run one after the other; a part that fails does not stop the others (their results show what is missing), and the job ends with the first error code
"$PY" "$HW/scripts/09_qc_figures.py" || { [ "$rc" = 0 ] && rc=3; }
"$PY" "$HW/scripts/09_workflow_figure.py" || { [ "$rc" = 0 ] && rc=3; }
bash "$HW/scripts/09_replicates.sh" || { [ "$rc" = 0 ] && rc=3; }
"$PY" "$HW/scripts/09_release.py" proc_r1 || { [ "$rc" = 0 ] && rc=4; }
"$PY" "$HW/scripts/09_resources.py" 2> "$LOGDIR/09_resources.err" || { echo "resources table not made (job accounting not available): $(tail -n 1 "$LOGDIR/09_resources.err")"; }   # a report: never makes the run FAILED; its error text is kept in the log folder
"$PY" "$HW/scripts/10_validate.py" check "$RESULTS" 2> "$LOGDIR/10_validate.err" || { echo "the comparison with the first analysis could not be written: $(tail -n 1 "$LOGDIR/10_validate.err")"; }   # a report: it never makes the run FAILED
[ "$rc" = 0 ] || { echo "[$(date)] FAILED 09_summary: a part of the summary failed (exit code $rc, see above); the other parts were made"; exit "$rc"; }
hw_end 09_summary
