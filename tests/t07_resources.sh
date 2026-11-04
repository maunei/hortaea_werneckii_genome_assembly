#!/bin/bash
# 09_resources.py with a mock sacct: tasks of array jobs are counted; a task that did not complete makes the job not completed (in either order); control assemblies are grouped by the ledger key
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"
printf 'pacbio\t5001\tafterok:5000\t02_pacbio_reads.sbatch\t--array=0-1\nsolo\t5002\t\t03_qc.sbatch\t\nbad_a\t5003\t\t05_align_subreads.sbatch\t\nbad_b\t5004\t\t05_align_subreads.sbatch\t\npolish_ctrl_canu\t5005\t\t05_polish.sbatch\t\npolish_r1\t5006\t\t05_polish.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"
mkdir -p "$W/hw/logs/5011_x"; printf 'Elapsed (wall clock) time (h:mm:ss or m:ss): 0:30:00\nMaximum resident set size (kbytes): 1048576\n' > "$W/hw/logs/5011_x/stage_a.time"   # the log folder of an array task is named with its raw job number
mkdir -p "$W/hw/logs/9999_y"; printf 'Elapsed (wall clock) time (h:mm:ss or m:ss): 0:30:00\nMaximum resident set size (kbytes): 1048576\n' > "$W/hw/logs/9999_y/stage_b.time"   # a log of a job that is not in the ledger
cat > "$W/bin/sacct" <<'M'
#!/bin/bash
cat <<'D'
5001_0|5011|COMPLETED|01:00:00|10:00:00|16|
5001_0.batch|5011.batch|COMPLETED|01:00:00|10:00:00|16|2000000K
5001_1|5001|COMPLETED|01:00:00|10:00:00|16|
5001_1.batch|5001.batch|COMPLETED|01:00:00|10:00:00|16|1000000K
5002|5002|COMPLETED|00:30:00|02:00:00|8|
5002.batch|5002.batch|COMPLETED|00:30:00|02:00:00|8|500000K
5003_0|5013|COMPLETED|01:00:00|01:00:00|4|
5003_1|5003|FAILED|01:00:00|01:00:00|4|
5004_0|5014|FAILED|01:00:00|01:00:00|4|
5004_1|5004|COMPLETED|01:00:00|01:00:00|4|
5005|5005|COMPLETED|01:00:00|03:00:00|4|
5006|5006|COMPLETED|01:00:00|05:00:00|4|
D
M
chmod +x "$W/bin/sacct"
PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > /dev/null 2>&1 || { echo "09_resources.py failed"; exit 1; }
python3 - "$W/hw/results/09_summary" <<'PY'
import json, sys, csv
d = sys.argv[1]
t = json.load(open(d + '/resources_totals.json'))
assert abs(t['total'] - 30.0) < 0.15, f"total core-hours {t['total']}: expected 30.0 (array 20 h, solo 2 h, polish_ctrl_canu 3 h, polish_r1 5 h; the two arrays with a failed task are not counted)"
assert abs(t.get('controls', 0) - 3.0) < 0.15, f"controls {t.get('controls')}: expected 3.0 (the polishing of the control assembly, by the ledger key)"
rows = {r['job']: r for r in csv.DictReader(open(d + '/resources_jobs.tsv'), delimiter='\t')}
assert rows['pacbio']['state'] == 'COMPLETED', rows['pacbio']
assert rows['bad_a']['state'] != 'COMPLETED' and rows['bad_b']['state'] != 'COMPLETED', 'a job with a failed task is reported as COMPLETED: ' + str((rows['bad_a']['state'], rows['bad_b']['state']))
st = list(csv.DictReader(open(d + '/resources_stages.tsv'), delimiter='\t'))
assert [r['stage'] for r in st] == ['stage_a'], 'time files: ' + str([r['stage'] for r in st])
PY
[ $? = 0 ] || exit 1
# an empty or failing sacct makes no table of zeros
printf '#!/bin/bash\nexit 1\n' > "$W/bin/sacct"; rm -rf "$W/hw/results"
PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > /dev/null 2>&1 && { echo "09_resources.py succeeded with a failing sacct"; exit 1; }
[ ! -s "$W/hw/results/09_summary/resources_totals.json" ] || { echo "a table of resources was written without accounting"; exit 1; }
exit 0
