#!/bin/bash
# FX-07: 06_collect.py and jobs/06_tests.sbatch:
# - when readback_align fails, readback.json, depth.json and their step markers are not used or reused, and the steps that need them are not run
# - the same for steps that need contiguity.json (miniprot, star)
# - tm() records the time of a command that failed
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# Part 1: 06_collect.py must ignore stale readback.json and depth.json when readback_align is in FAILED_STEPS
mkdir -p "$W/res1"
echo '{"all": {"total_bp": 5000}}' > "$W/res1/contiguity.json"
echo '{"reads_total": 100, "frac_reads_aligned_ge80pct": 0.99}' > "$W/res1/readback.json"
echo '{"frac_0_5_to_1_5": 0.98}' > "$W/res1/depth.json"
python3 "$HW/scripts/06_collect.py" "$W/res1" proc_r1 reads.fq SRR1 "readback_align" || { echo "06_collect.py failed"; exit 1; }
python3 - "$W/res1/summary.json" <<'PY' || exit 1
import json, sys
s = json.load(open(sys.argv[1]))
assert s['contiguity'] is not None, "good contiguity.json was dropped"
if s['readback'] is not None or s['depth'] is not None:
    sys.exit(f"FAIL: 06_collect.py used stale readback.json or depth.json when readback_align failed: readback={s['readback']}, depth={s['depth']}")
PY

# Part 2: tm() in jobs/06_tests.sbatch must record the timing of a failing command and return its non-zero exit code
mkdir -p "$W/tmp2" "$W/res2"
printf 'step\tseconds\tmax_rss_gb_largest_process\n' > "$W/res2/timings.tsv"
(
  TMP="$W/tmp2"; RES="$W/res2"; TIMEV=/usr/bin/time; FAILED=""; BIG="$W/big2"; FORCE=0; mkdir -p "$BIG/steps"
  eval "$(sed -n '/^tm() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"
  eval "$(sed -n '/^step() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"
  s_fail_tm() { tm bad_cmd bash -c 'exit 7'; }
  step fail_tm s_fail_tm > /dev/null 2>&1
  [ "${FAILED# }" = "fail_tm" ] || { echo "FAIL: step() did not record fail_tm in FAILED (got '$FAILED')"; exit 1; }
  grep -q '^bad_cmd	' "$RES/timings.tsv" || { echo "FAIL: tm() did not record bad_cmd in timings.tsv when command failed"; exit 1; }
) || exit 1

# Part 3: in jobs/06_tests.sbatch, when readback_align or contiguity fails, dependent steps do not run and their stale markers/files are not reused
mkdir -p "$W/res3" "$W/big3/steps" "$W/tmp3" "$W/log3"
touch "$W/big3/steps/readback_stats.done" "$W/big3/steps/depth.done" "$W/big3/steps/miniprot.done" "$W/big3/steps/star.done"
echo '{"reads_total": 100}' > "$W/res3/readback.json"
echo '{"frac_0_5_to_1_5": 0.9}' > "$W/res3/depth.json"
echo '{"frac_proteins_whole": 0.9}' > "$W/res3/miniprot.json"
echo '{"input_pairs": 100, "frac_unique": 0.9}' > "$W/res3/star.json"

(
  RES="$W/res3"; BIG="$W/big3"; TMP="$W/tmp3"; LOGDIR="$W/log3"; FORCE=0; FAILED=""; TIMEV=/usr/bin/time; PY=python3; SCR="$HW/scripts"; ASM=test; PB_READS=reads.fq; RNA_RUN=SRR1
  printf 'step\tseconds\tmax_rss_gb_largest_process\n' > "$RES/timings.tsv"
  eval "$(sed -n '/^tm() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"
  eval "$(sed -n '/^step() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"
  RAN_FILE="$W/ran_steps"; : > "$RAN_FILE"
  s_contiguity()     { false; }
  s_telomeres()      { echo '{"telomeres": 1}' > "$RES/telomeres.json"; }
  s_busco()          { echo '{"complete_percent": 97.0}' > "$RES/busco.json"; }
  s_readback_align() { rm -f "$BIG/readback.bam"; false; }
  s_readback_stats() { echo readback_stats >> "$RAN_FILE"; }
  s_depth()          { echo depth >> "$RAN_FILE"; }
  s_selfalign()      { echo '{"false_duplication_fraction": 0.0}' > "$RES/redundancy.json"; }
  s_miniprot()       { echo miniprot >> "$RAN_FILE"; }
  s_star()           { echo star >> "$RAN_FILE"; }

  eval "$(sed -n '/^step contiguity/,/^"$PY" "\$SCR\/06_collect.py"/p' "$HW/jobs/06_tests.sbatch")"
  [ ! -s "$RAN_FILE" ] || { echo "FAIL: dependent steps ran after prerequisite failed:"; cat "$RAN_FILE"; exit 1; }
  for m in readback_stats depth miniprot star; do
    [ ! -e "$BIG/steps/$m.done" ] || { echo "FAIL: stale marker $m.done was left behind"; exit 1; }
  done
  python3 - "$RES/summary.json" <<'PY' || exit 1
import json, sys
s = json.load(open(sys.argv[1]))
assert s['telomeres'] is not None and s['busco'] is not None, "independent steps should be collected"
for k in ('contiguity', 'readback', 'depth', 'miniprot', 'star'):
    if s.get(k) is not None:
        sys.exit(f"FAIL: stale {k} was kept in summary.json after prerequisite step failed")
PY
) || exit 1
exit 0
