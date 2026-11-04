#!/bin/bash
# FX-10 (09_resources.py): accounting that is missing for some of the expected job ids,
# or a failing/empty sacct, is an error (makes no zero/partial table); complete output still succeeds.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"

cat > "$W/hw/jobs/submitted_by_submit_all.tsv" <<'EOF'
pacbio	5001	afterok:5000	02_pacbio_reads.sbatch	--array=0-1
solo	5002	afterok:5001	03_qc.sbatch	
EOF

cat > "$W/bin/sacct" <<'M'
#!/bin/bash
[ "${MOCK_MODE:-ok}" = "fail" ] && { echo "sacct: error: slurmdbd unreachable" >&2; exit 1; }
[ "${MOCK_MODE:-ok}" = "empty" ] && exit 0
python3 - "$@" <<'PY'
import os, sys
fmt = "JobID,State,Elapsed,TotalCPU,AllocCPUS,MaxRSS"
args = sys.argv[1:]
for i, a in enumerate(args):
    if a in ("-o", "--format") and i + 1 < len(args):
        fmt = args[i + 1]
    elif a.startswith("--format="):
        fmt = a.split("=", 1)[1]
cols = fmt.split(",")
rows = [
    {"JobID": "5001_0",       "JobIDRaw": "5001",       "State": "COMPLETED", "Elapsed": "01:00:00", "TotalCPU": "10:00:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "5001_0.batch", "JobIDRaw": "5001.batch", "State": "COMPLETED", "Elapsed": "01:00:00", "TotalCPU": "10:00:00", "AllocCPUS": "16", "MaxRSS": "1000000K"},
]
if os.environ.get("MOCK_MODE", "ok") in ("ok", "arrshort"):
    rows += [
        {"JobID": "5001_1",       "JobIDRaw": "5009",       "State": "COMPLETED", "Elapsed": "01:00:00", "TotalCPU": "10:00:00", "AllocCPUS": "16", "MaxRSS": ""},
    ] if os.environ.get("MOCK_MODE") == "ok" else []
if os.environ.get("MOCK_MODE", "ok") in ("ok", "arrshort"):
    rows += [
        {"JobID": "5002",       "JobIDRaw": "5002",       "State": "COMPLETED", "Elapsed": "00:30:00", "TotalCPU": "02:00:00", "AllocCPUS": "8", "MaxRSS": ""},
        {"JobID": "5002.batch", "JobIDRaw": "5002.batch", "State": "COMPLETED", "Elapsed": "00:30:00", "TotalCPU": "02:00:00", "AllocCPUS": "8", "MaxRSS": "500000K"},
    ]
for r in rows:
    print("|".join(r.get(c, "") for c in cols))
PY
M
chmod +x "$W/bin/sacct"

# 1. Positive check: complete sacct output must succeed
MOCK_MODE=ok PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/ok.out" 2>&1 || {
  echo "09_resources.py failed on valid complete sacct output:"
  cat "$W/ok.out"
  exit 1
}
[ -s "$W/hw/results/09_summary/resources_totals.json" ] || { echo "resources_totals.json not written on valid run"; exit 1; }

# 2. Failing sacct, empty sacct, and partial sacct (missing job 5002) must all fail and make no zero/partial table
for mode in fail empty partial arrshort; do
  rm -rf "$W/hw/results/09_summary"
  if MOCK_MODE="$mode" PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/$mode.out" 2>&1; then
    echo "FAIL: 09_resources.py succeeded when sacct mode=$mode"
    exit 1
  fi
  if [ -e "$W/hw/results/09_summary/resources_totals.json" ] || [ -e "$W/hw/results/09_summary/resources_jobs.tsv" ]; then
    echo "FAIL: 09_resources.py left a partial/zero table on disk when sacct mode=$mode"
    exit 1
  fi
done
exit 0
