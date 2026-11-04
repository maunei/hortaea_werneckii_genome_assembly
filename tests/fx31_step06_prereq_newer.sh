#!/bin/bash
# FX-31 (B-06): step() in jobs/06_tests.sbatch re-runs a dependent step when its prerequisite
# marker is newer than its own marker, skips it when its own marker is newer, and refuses
# to run it when the prerequisite failed in the current run.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

BIG="$W/big"
mkdir -p "$BIG/steps"
FORCE=0
FAILED=""

eval "$(sed -n '/^step() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"

RAN_LOG="$W/ran.log"
: > "$RAN_LOG"
s_contiguity() { echo "contiguity" >> "$RAN_LOG"; }
s_telomeres()  { echo "telomeres" >> "$RAN_LOG"; }

# 1. Both markers exist and telomeres.done is newer than contiguity.done -> skipped
touch "$BIG/steps/contiguity.done" "$BIG/steps/telomeres.done"
python3 - "$BIG/steps/contiguity.done" "$BIG/steps/telomeres.done" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now - 120, now - 120))
os.utime(sys.argv[2], (now - 60, now - 60))
PY

step telomeres s_telomeres contiguity > "$W/out1.txt" 2>&1
[ ! -s "$RAN_LOG" ] || { echo "FAIL: telomeres should be skipped when its marker is newer than contiguity.done" >&2; exit 1; }
grep -q "already done, skipped" "$W/out1.txt" || { echo "FAIL: expected skip message" >&2; exit 1; }

# 2. Prerequisite contiguity.done is newer than telomeres.done -> telomeres must run again
python3 - "$BIG/steps/contiguity.done" "$BIG/steps/telomeres.done" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now, now))
os.utime(sys.argv[2], (now - 60, now - 60))
PY

step telomeres s_telomeres contiguity > "$W/out2.txt" 2>&1
grep -qx "telomeres" "$RAN_LOG" || {
  echo "FAIL: telomeres did not re-run when prerequisite contiguity.done was newer" >&2
  cat "$W/out2.txt" >&2
  exit 1
}
[ -e "$BIG/steps/telomeres.done" ] || { echo "FAIL: telomeres.done not recreated after re-run" >&2; exit 1; }

# 3. Prerequisite listed in FAILED -> dependent step must not run even if stale prerequisite marker exists
: > "$RAN_LOG"
FAILED=" contiguity"
step telomeres s_telomeres contiguity > "$W/out3.txt" 2>&1
[ ! -s "$RAN_LOG" ] || { echo "FAIL: telomeres ran despite contiguity in FAILED" >&2; exit 1; }
[ ! -e "$BIG/steps/telomeres.done" ] || { echo "FAIL: stale telomeres.done was not removed when prerequisite failed" >&2; exit 1; }
[[ " $FAILED " == *" telomeres "* ]] || { echo "FAIL: telomeres not added to FAILED" >&2; exit 1; }

echo "PASS"
