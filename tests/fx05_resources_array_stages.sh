#!/bin/bash
# FX-05: 09_resources.py keeps the .time files of all array tasks (25 of 25 pbalign*.time in run 9)
# by mapping raw task ids (JobIDRaw) to their ledger job; .time files of jobs not in the ledger are ignored.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results"

cat > "$W/hw/jobs/submitted_by_submit_all.tsv" <<'EOF'
proc_r1	2132962	afterok:2132961	04_procedure.sbatch	--export=ALL,RUN=r1,THREADS=16
align_r1	2132968	afterok:2132962	05_align_subreads.sbatch	--export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1,THREADS=16 --cpus-per-task=16
EOF

# Create 5 array task log folders with realistic Slurm raw task IDs (tasks 0..3 have distinct JobIDRaw; task 4 has master JobID)
for pair in "2147082:SRR5086620" "2147083:SRR5086623" "2147084:SRR5086626" "2147085:SRR5086627" "2132968:SRR5086628"; do
  raw="${pair%%:*}"; run="${pair##*:}"
  mkdir -p "$W/hw/logs/${raw}_05_align_2026-11-02"
  printf '\tElapsed (wall clock) time (h:mm:ss or m:ss): 0:06:00\n\tMaximum resident set size (kbytes): 4194304\n' > "$W/hw/logs/${raw}_05_align_2026-11-02/pbalign_${run}.time"
done
mkdir -p "$W/hw/logs/2132962_04_procedure_2026-11-02"
printf '\tElapsed (wall clock) time (h:mm:ss or m:ss): 0:30:00\n\tMaximum resident set size (kbytes): 8388608\n' > "$W/hw/logs/2132962_04_procedure_2026-11-02/canu_asm.time"
# Non-ledger job log folder that must be ignored
mkdir -p "$W/hw/logs/9999999_05_align_2026-11-01"
printf '\tElapsed (wall clock) time (h:mm:ss or m:ss): 0:10:00\n\tMaximum resident set size (kbytes): 1048576\n' > "$W/hw/logs/9999999_05_align_2026-11-01/pbalign_stale.time"

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
    {"JobID": "2132962",         "JobIDRaw": "2132962",       "State": "COMPLETED", "Elapsed": "00:30:00", "TotalCPU": "08:00:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132962.batch",   "JobIDRaw": "2132962.batch", "State": "COMPLETED", "Elapsed": "00:30:00", "TotalCPU": "08:00:00", "AllocCPUS": "16", "MaxRSS": "8388608K"},
    {"JobID": "2132968_0",       "JobIDRaw": "2147082",       "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132968_0.batch", "JobIDRaw": "2147082.batch", "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": "4194304K"},
    {"JobID": "2132968_1",       "JobIDRaw": "2147083",       "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132968_1.batch", "JobIDRaw": "2147083.batch", "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": "4194304K"},
    {"JobID": "2132968_2",       "JobIDRaw": "2147084",       "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132968_2.batch", "JobIDRaw": "2147084.batch", "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": "4194304K"},
    {"JobID": "2132968_3",       "JobIDRaw": "2147085",       "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132968_3.batch", "JobIDRaw": "2147085.batch", "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": "4194304K"},
    {"JobID": "2132968_4",       "JobIDRaw": "2132968",       "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": ""},
    {"JobID": "2132968_4.batch", "JobIDRaw": "2132968.batch", "State": "COMPLETED", "Elapsed": "00:06:00", "TotalCPU": "01:30:00", "AllocCPUS": "16", "MaxRSS": "4194304K"},
]
for r in rows:
    print("|".join(r.get(c, "") for c in cols))
PY
M
chmod +x "$W/bin/sacct"

PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/out.txt" 2>&1 || {
  echo "09_resources.py failed:"
  cat "$W/out.txt"
  exit 1
}

STAGES="$W/hw/results/09_summary/resources_stages.tsv"
grep -q "canu_asm" "$STAGES" || { echo "FAIL: canu_asm missing from resources_stages.tsv"; exit 1; }
! grep -q "pbalign_stale" "$STAGES" || { echo "FAIL: non-ledger pbalign_stale was kept in resources_stages.tsv"; exit 1; }
n_pb=$(grep -c $'\tpbalign_SRR' "$STAGES" || true)
[ "$n_pb" -eq 5 ] || {
  echo "FAIL: expected 5 pbalign_SRR* rows in resources_stages.tsv, got $n_pb"
  cat "$STAGES"
  exit 1
}
exit 0
