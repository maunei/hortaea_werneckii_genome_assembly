# Logging helpers in the style of the cluster job scripts of the project (source after config.sh).
# hw_start NAME : creates the log folder LOGS_BASE/<jobid>_<name>_<timestamp>, copies the running script there and prints the start markers.
hw_start() {
  local name="$1"; local ts; ts="$(date +'%Y-%m-%d_%H-%M-%S')"
  export LOGDIR="${LOGS_BASE}/${SLURM_JOB_ID:-local}_${name}_${ts}"
  mkdir -p "$LOGDIR"; cp "${BASH_SOURCE[1]}" "$LOGDIR/" 2>/dev/null || true
  echo "[$(date)] Starting ${name}"; echo "Node: ${SLURMD_NODENAME:-$(hostname)}"; echo "Job ID: ${SLURM_JOB_ID:-none}"; echo "LOGDIR: ${LOGDIR}"
}
hw_end() { echo "[$(date)] Finished $1"; }
