#!/bin/bash
# Regression test for Round D fixes D-02 and D-03 in setup_and_run_all.sh:
# 1. Submission lock: stage_run takes an exclusive non-blocking lock on
#    jobs/.submission.lock; a second concurrent stage_run must fail immediately
#    without touching jobs/submitted_by_submit_all.tsv or submitting jobs.
# 2. Queue snapshot: stage_run queries squeue -h -u "$USER" -o "%i" once; if
#    squeue fails (non-zero exit), stage_run must stop with an error and keep
#    the existing ledger intact; if squeue reports an old ledger job still in
#    the queue (including array task 123_4 or bracketed 123_[5-9]), stage_run
#    must refuse to start.
set -euo pipefail
HW="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PY:-python3}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Create an isolated copy of the workflow root to test setup_and_run_all.sh
W="$T/hw"
mkdir -p "$W/config" "$W/jobs" "$W/scripts" "$W/envs" "$W/input" "$W/logs" "$T/bin" "$T/work" "$T/envs" "$T/dbs" "$T/results"
cp "$HW/setup_and_run_all.sh" "$W/setup_and_run_all.sh"
cp "$HW/config/"*.sh "$W/config/"

cat > "$W/settings.yaml" <<EOF
account: def-test
mail_when: NONE
mail_address: test@example.com
work_dir: $T/work
envs_dir: $T/envs
dbs_dir: $T/dbs
EOF

cat > "$W/config/local.sh" <<EOF
export HW_WORK=$T/work
export HW_ENVS=$T/envs
export HW_DBS=$T/dbs
export HW_ACCOUNT=def-test
export HW_MAIL=test@example.com
export HW_MAIL_WHEN=NONE
EOF

cat > "$W/scripts/submit_all.sh" <<'EOF'
#!/bin/bash
printf 'summary\t9001\t\t09_summary.sbatch\t\n' > "$LEDGER"
EOF
chmod +x "$W/scripts/submit_all.sh"

# Existing ledger from a previous run
printf 'pacbio\t5550\t\t02_pacbio_reads.sbatch\t--array=0-4\n' > "$W/jobs/submitted_by_submit_all.tsv"
cp "$W/jobs/submitted_by_submit_all.tsv" "$T/ledger_orig.tsv"

# Stub squeue for Case 1 (no jobs in queue, but lock held)
cat > "$T/bin/squeue" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$T/bin/squeue"

# Case 1: Another process holds jobs/.submission.lock -> stage_run must fail immediately and keep ledger
(
  flock -n 9
  rc=0
  PATH="$T/bin:$PATH" bash "$W/setup_and_run_all.sh" run "$W/settings.yaml" > "$T/case1.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: stage_run succeeded while another process held jobs/.submission.lock" >&2
    exit 1
  fi
  grep -q "another submission from this folder is still in progress" "$T/case1.log" || {
    echo "FAIL: expected submission lock error message, got:" >&2
    cat "$T/case1.log" >&2
    exit 1
  }
) 9>> "$W/jobs/.submission.lock"
cmp -s "$W/jobs/submitted_by_submit_all.tsv" "$T/ledger_orig.tsv" || {
  echo "FAIL: ledger was modified when submission lock was held" >&2
  exit 1
}

# Case 2: squeue fails (exits non-zero) -> stage_run must stop with an error and keep ledger
cat > "$T/bin/squeue" <<'EOF'
#!/bin/bash
echo "slurm_load_jobs error: Socket timed out" >&2
exit 1
EOF
chmod +x "$T/bin/squeue"

rc=0
PATH="$T/bin:$PATH" bash "$W/setup_and_run_all.sh" run "$W/settings.yaml" > "$T/case2.log" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "FAIL: stage_run succeeded when squeue failed" >&2
  exit 1
fi
grep -q "cannot verify the previous attempt in the queue; ledger preserved" "$T/case2.log" || {
  echo "FAIL: expected squeue failure message, got:" >&2
  cat "$T/case2.log" >&2
  exit 1
}
cmp -s "$W/jobs/submitted_by_submit_all.tsv" "$T/ledger_orig.tsv" || {
  echo "FAIL: ledger was modified when squeue failed" >&2
  exit 1
}

# Case 3: squeue succeeds and reports 5550_[2-4] still in queue -> stage_run must refuse and keep ledger
cat > "$T/bin/squeue" <<'EOF'
#!/bin/bash
if [[ "$*" == *"hw_09_summary"* ]]; then exit 0; fi
printf '9999\n5550_[2-4]\n'
EOF
chmod +x "$T/bin/squeue"

rc=0
PATH="$T/bin:$PATH" bash "$W/setup_and_run_all.sh" run "$W/settings.yaml" > "$T/case3.log" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "FAIL: stage_run succeeded when old array job 5550_[2-4] was still in queue" >&2
  exit 1
fi
grep -q "jobs of an earlier attempt are still in the queue" "$T/case3.log" || {
  echo "FAIL: expected active-queue refusal message, got:" >&2
  cat "$T/case3.log" >&2
  exit 1
}
cmp -s "$W/jobs/submitted_by_submit_all.tsv" "$T/ledger_orig.tsv" || {
  echo "FAIL: ledger was modified when old job was still in queue" >&2
  exit 1
}

echo "fx57_stage_run_lock_and_squeue: OK"
