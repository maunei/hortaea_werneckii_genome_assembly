#!/bin/bash
# 09_resources.py with a mock sacct: the tasks of an array job are counted
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results"
printf 'pacbio\t5001\tafterok:5000\t02_pacbio_reads.sbatch\nsolo\t5002\t\t03_qc.sbatch\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"
cat > "$W/bin/sacct" <<'M'
#!/bin/bash
cat <<'D'
5001_0|COMPLETED|01:00:00|10:00:00|16|
5001_0.batch|COMPLETED|01:00:00|10:00:00|16|2000000K
5001_1|COMPLETED|01:00:00|10:00:00|16|
5001_1.batch|COMPLETED|01:00:00|10:00:00|16|1000000K
5002|COMPLETED|00:30:00|02:00:00|8|
5002.batch|COMPLETED|00:30:00|02:00:00|8|500000K
D
M
chmod +x "$W/bin/sacct"
PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > /dev/null 2>&1 || { echo "09_resources.py failed"; exit 1; }
python3 - "$W/hw/results/09_summary/resources_totals.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); tot = t['total']
assert abs(tot - 22.0) < 0.15, f'total core-hours {tot}, expected 22.0 (two array tasks of 10 h and one job of 2 h)'
PY
