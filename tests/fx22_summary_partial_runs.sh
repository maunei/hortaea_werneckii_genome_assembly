#!/bin/bash
# FX-22 (added from A-R2-08c, A-R2-08d):
# 1. 09_summary.py: when only 1 replicate has a measure, it does not declare 'better' or 'worse' from noise=0.0;
#    and a replicate missing n50 is still counted in runs for measures it does have.
# 2. 09_summary.sbatch: if an earlier step (e.g. 09_release.py when proc_r1 FASTA is absent) fails,
#    09_replicates.sh, 09_resources.py, and 10_validate.py still run before the job exits non-zero.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/results/06_tests/hw2" "$W/results/06_tests/proc_r1" "$W/results/06_tests/proc_r2" "$W/work"

cat > "$W/results/06_tests/hw2/summary.json" <<'EOF'
{"contiguity": {"all": {"n50": 500000, "ng50": 500000, "aun": 600000, "l50": 30, "contigs": 250, "total_bp": 50000000, "longest": 2000000}}, "busco": {"complete_percent": 97.0}}
EOF
cat > "$W/results/06_tests/proc_r1/summary.json" <<'EOF'
{"contiguity": {"all": {"n50": 540000, "ng50": 540000, "aun": 650000, "l50": 28, "contigs": 212, "total_bp": 49900000, "longest": 2100000}}, "busco": {"complete_percent": 97.6}}
EOF
# proc_r2 has busco but contiguity failed (contiguity is null)
cat > "$W/results/06_tests/proc_r2/summary.json" <<'EOF'
{"contiguity": null, "busco": {"complete_percent": 97.6}}
EOF

HW="$HW" RESULTS="$W/results" WORK="$W/work" python3 "$HW/scripts/09_summary.py" > "$W/out.txt" 2>&1 || {
  echo "09_summary.py failed:"
  cat "$W/out.txt"
  exit 1
}

python3 - "$W/results/09_summary/noise_scale.tsv" <<'PY' || exit 1
import csv, sys
rows = {r['measure']: r for r in csv.DictReader(open(sys.argv[1]), delimiter='\t')}
if int(rows['busco_complete']['runs']) < 2:
    sys.exit(f"FAIL: proc_r2 had busco_complete but was excluded from runs because its n50 was None: {rows['busco_complete']}")
if rows['n50']['state'] in ('better', 'worse'):
    sys.exit(f"FAIL: n50 with only 1 run (runs={rows['n50']['runs']}) was classified as {rows['n50']['state']!r} from noise=0.0")
PY

# Exercise the actual batch wrapper too: Python-table tests above do not cover it.
python3 - "$HW/jobs/09_summary.sbatch" "$W/batch" <<'PYJOB'
from pathlib import Path
import os, subprocess, sys
source, root = Path(sys.argv[1]), Path(sys.argv[2])
for name in ('config','scripts','logs','results'): (root/name).mkdir(parents=True, exist_ok=True)
(root/'job.sh').write_text(source.read_text())
(root/'config/modules.sh').write_text(':\n')
(root/'config/config.sh').write_text('export RESULTS="$HW/results" PY="$HW/fake_python"\n')
(root/'config/lib.sh').write_text('hw_start() { export LOGDIR="$HW/logs"; }; hw_end() { :; }\n')
body = '#!/bin/bash\nn=$(basename "$1"); echo "$n" >> "$CALLS"; [ "$n" != "$FAIL_COMPONENT" ] || exit 42; exit 0\n'
p=root/'fake_python'; p.write_text(body); p.chmod(0o755)
p=root/'scripts/09_replicates.sh'; p.write_text('#!/bin/bash\necho 09_replicates.sh >> "$CALLS"; [ "$FAIL_COMPONENT" != 09_replicates.sh ] || exit 42; exit 0\n')
expected=['09_summary.py','09_qc_figures.py','09_workflow_figure.py','09_replicates.sh','09_release.py','09_resources.py','10_validate.py']
for fail, rc in [('none',0),('09_qc_figures.py',3),('09_replicates.sh',3),('09_release.py',4)]:
    calls=root/(fail+'.calls')
    env=dict(os.environ, SLURM_SUBMIT_DIR=str(root), CALLS=str(calls), FAIL_COMPONENT=fail)
    result=subprocess.run(['bash',str(root/'job.sh')],env=env,capture_output=True,text=True)
    seen=calls.read_text().splitlines() if calls.exists() else []
    assert result.returncode==rc, (fail,result.returncode,result.stdout,result.stderr)
    assert seen==expected, (fail,'independent helpers skipped',seen)
PYJOB
