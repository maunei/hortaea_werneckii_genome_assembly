#!/bin/bash
# FX-04: 09_resources.py: an array job with any task not COMPLETED gets a state that is not COMPLETED,
# and its CPU is not counted as completed; the order of the tasks does not matter.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"

# Ledger: two array jobs (5001: task 0 COMPLETED, task 1 FAILED; 5002: task 0 TIMEOUT, task 1 COMPLETED) and one COMPLETED job (5003)
cat > "$W/hw/jobs/submitted_by_submit_all.tsv" <<'EOF'
align_r1	5001	afterok:5000	05_align_subreads.sbatch	--export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1
align_r2	5002	afterok:5000	05_align_subreads.sbatch	--export=ALL,RAW=proc_r2_raw,OUTNAME=proc_r2
proc_r1	5003	afterok:5000	04_procedure.sbatch	--export=ALL,RUN=r1,THREADS=16
EOF

cat > "$W/bin/sacct" <<'M'
#!/bin/bash
python3 - "$@" <<'PY'
import sys
fmt = "JobID,State,Elapsed,TotalCPU,AllocCPUS,MaxRSS"
args = sys.argv[1:]
for i, a in enumerate(args):
    if a in ("-o", "--format") and i + 1 < len(args):
        fmt = args[i + 1]
    elif a.startswith("--format="):
        fmt = a.split("=", 1)[1]
cols = fmt.split(",")
rows = [
    {"JobID": "5001_0",       "JobIDRaw": "5010",       "JobName": "hw_05_align", "State": "COMPLETED", "Elapsed": "01:00:00", "ElapsedRaw": "3600", "TotalCPU": "10:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "",         "ReqMem": "64G", "NodeList": "node1"},
    {"JobID": "5001_0.batch", "JobIDRaw": "5010.batch", "JobName": "batch",       "State": "COMPLETED", "Elapsed": "01:00:00", "ElapsedRaw": "3600", "TotalCPU": "10:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "2000000K", "ReqMem": "64G", "NodeList": "node1"},
    {"JobID": "5001_1",       "JobIDRaw": "5001",       "JobName": "hw_05_align", "State": "FAILED",    "Elapsed": "00:30:00", "ElapsedRaw": "1800", "TotalCPU": "04:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "",         "ReqMem": "64G", "NodeList": "node1"},
    {"JobID": "5001_1.batch", "JobIDRaw": "5001.batch", "JobName": "batch",       "State": "FAILED",    "Elapsed": "00:30:00", "ElapsedRaw": "1800", "TotalCPU": "04:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "1000000K", "ReqMem": "64G", "NodeList": "node1"},
    {"JobID": "5002_0",       "JobIDRaw": "5020",       "JobName": "hw_05_align", "State": "TIMEOUT",   "Elapsed": "06:00:00", "ElapsedRaw": "21600","TotalCPU": "08:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "",         "ReqMem": "64G", "NodeList": "node2"},
    {"JobID": "5002_0.batch", "JobIDRaw": "5020.batch", "JobName": "batch",       "State": "TIMEOUT",   "Elapsed": "06:00:00", "ElapsedRaw": "21600","TotalCPU": "08:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "1000000K", "ReqMem": "64G", "NodeList": "node2"},
    {"JobID": "5002_1",       "JobIDRaw": "5002",       "JobName": "hw_05_align", "State": "COMPLETED", "Elapsed": "01:00:00", "ElapsedRaw": "3600", "TotalCPU": "10:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "",         "ReqMem": "64G", "NodeList": "node2"},
    {"JobID": "5002_1.batch", "JobIDRaw": "5002.batch", "JobName": "batch",       "State": "COMPLETED", "Elapsed": "01:00:00", "ElapsedRaw": "3600", "TotalCPU": "10:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "2000000K", "ReqMem": "64G", "NodeList": "node2"},
    {"JobID": "5003",         "JobIDRaw": "5003",       "JobName": "hw_04_proc",  "State": "COMPLETED", "Elapsed": "00:30:00", "ElapsedRaw": "1800", "TotalCPU": "02:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "",         "ReqMem": "100G","NodeList": "node3"},
    {"JobID": "5003.batch",   "JobIDRaw": "5003.batch", "JobName": "batch",       "State": "COMPLETED", "Elapsed": "00:30:00", "ElapsedRaw": "1800", "TotalCPU": "02:00:00", "AllocCPUS": "16", "NCPUS": "16", "MaxRSS": "500000K",  "ReqMem": "100G","NodeList": "node3"},
]
for r in rows:
    print("|".join(r.get(c, "") for c in cols))
PY
M
chmod +x "$W/bin/sacct"

PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/out.txt" 2>&1 || {
  echo "09_resources.py failed unexpectedly:"
  cat "$W/out.txt"
  exit 1
}

python3 - "$W/hw/results/09_summary/resources_jobs.tsv" "$W/hw/results/09_summary/resources_totals.json" <<'PY'
import csv, json, sys
jobs = {r['job']: r for r in csv.DictReader(open(sys.argv[1]), delimiter='\t')}
tot = json.load(open(sys.argv[2]))
assert 'proc_r1' in jobs and jobs['proc_r1']['state'] == 'COMPLETED', f"proc_r1 should be COMPLETED: {jobs.get('proc_r1')}"
if jobs['align_r1']['state'] == 'COMPLETED':
    sys.exit(f"FAIL: align_r1 (task 0 COMPLETED, task 1 FAILED) got state COMPLETED in resources_jobs.tsv")
if jobs['align_r2']['state'] == 'COMPLETED':
    sys.exit(f"FAIL: align_r2 (task 0 TIMEOUT, task 1 COMPLETED) got state COMPLETED in resources_jobs.tsv")
if abs(tot.get('total', 0) - 2.0) > 0.15:
    sys.exit(f"FAIL: total completed core-hours is {tot.get('total')}, expected 2.0 (failed array jobs were counted)")
PY
