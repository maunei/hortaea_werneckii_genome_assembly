# Logging helpers in the style of the cluster job scripts of the project (source after config.sh).
# hw_start NAME : creates the log folder LOGS_BASE/<jobid>_<name>_<timestamp>, copies the running script there and prints the start markers.
hw_start() {
  local name="$1"; local ts; ts="$(date +'%Y-%m-%d_%H-%M-%S')"
  export LOGDIR="${LOGS_BASE}/${SLURM_JOB_ID:-local}_${name}_${ts}"
  mkdir -p "$LOGDIR"; cp "${BASH_SOURCE[1]}" "$LOGDIR/" 2>/dev/null || true
  echo "[$(date)] Starting ${name}"; echo "Node: ${SLURMD_NODENAME:-$(hostname)}"; echo "Job ID: ${SLURM_JOB_ID:-none}"; echo "LOGDIR: ${LOGDIR}"
}
hw_end() {   # hw_end NAME : ends the job with an error when a Python error (Traceback) was written to the log of the job by a step whose exit status was not checked
  local f; f="$(scontrol show job "${SLURM_JOB_ID:-0}" 2>/dev/null | sed -n 's/^ *StdOut=//p' | head -1)"
  if [ -n "$f" ] && [ -f "$f" ] && grep -q '^Traceback (most recent call last)' "$f"; then echo "[$(date)] FAILED $1: a Python error is shown above"; exit 1; fi
  echo "[$(date)] Finished $1"
}
