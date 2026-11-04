#!/bin/bash
# FX-06: 09_resources.py: the control assemblies' polishing jobs (ledger keys *_ctrl_*)
# are in the group controls; the total is unchanged (228.7 for run 9).
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"

cat > "$W/hw/jobs/submitted_by_submit_all.tsv" <<'EOF'
proc_r1	6001	afterok:6000	04_procedure.sbatch	--export=ALL,RUN=r1,THREADS=16
align_r1	6002	afterok:6001	05_align_subreads.sbatch	--export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1
polish_r1	6003	afterok:6002	05_polish.sbatch	--export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1
ctrl_canu	6004	afterok:6000	04_control_canu.sbatch	
align_ctrl_canu	6005	afterok:6004	05_align_subreads.sbatch	--export=ALL,RAW=ctrl_canu,OUTNAME=ctrl_canu_quiver
polish_ctrl_canu	6006	afterok:6005	05_polish.sbatch	--export=ALL,RAW=ctrl_canu,OUTNAME=ctrl_canu_quiver
remove_ctrl_canu	6007	afterok:6006	05_remove_contaminant_contigs.sbatch	--export=ALL,OUTNAME=ctrl_canu_quiver
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
# Procedure: 6001 (10h) + 6002 (4h) + 6003 (6h) = 20.0 core-h
# Controls:  6004 (12h) + 6005 (3h) + 6006 (5h) + 6007 (1h) = 21.0 core-h
# Total = 41.0 core-h
spec = [
    ("6001", "10:00:00"),
    ("6002", "04:00:00"),
    ("6003", "06:00:00"),
    ("6004", "12:00:00"),
    ("6005", "03:00:00"),
    ("6006", "05:00:00"),
    ("6007", "01:00:00"),
]
for jid, tcpu in spec:
    for suf, rss in (("", ""), (".batch", "1000000K")):
        r = {"JobID": jid + suf, "JobIDRaw": jid + suf, "State": "COMPLETED", "Elapsed": "01:00:00", "TotalCPU": tcpu, "AllocCPUS": "16", "MaxRSS": rss}
        print("|".join(r.get(c, "") for c in cols))
PY
M
chmod +x "$W/bin/sacct"

PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/out.txt" 2>&1 || {
  echo "09_resources.py failed:"
  cat "$W/out.txt"
  exit 1
}

python3 - "$W/hw/results/09_summary/resources_totals.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1]))
assert abs(t.get('total', 0) - 41.0) < 0.15, f"expected total 41.0, got {t}"
if abs(t.get('controls', 0) - 21.0) > 0.15 or abs(t.get('procedure', 0) - 20.0) > 0.15:
    sys.exit(f"FAIL: control polishing jobs were counted in procedure instead of controls: {t} (expected procedure=20.0, controls=21.0)")
PY
