#!/bin/bash
# Runs the tests of this folder (see README.md). Usage: bash tests/run_tests.sh [filter]   (filter: t03, 03 or t03_settings.sh; the families tNN_*.sh and fxNN_*.sh are both run)
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export HW="$(cd "$T/.." && pwd)"; fail=0; ran=0
# the tests make many small files: on a cluster the temporary folder goes to the local disk of the node (a shared disk can be thousands of times slower and the tests have time limits)
[ -n "${SLURM_TMPDIR:-}" ] && [ -d "$SLURM_TMPDIR" ] && export TMPDIR="$SLURM_TMPDIR"
f="${1:-}"; f="${f%.sh}"   # filter: t03 = the test t03 (family tNN), fx03 = the test of the family fxNN, 03 = both
case "$f" in fx*) pats=("$T/${f}"*.sh);; t*) pats=("$T/${f}"*.sh);; *) pats=("$T/t${f}"*.sh "$T/fx${f}"*.sh);; esac
for t in "${pats[@]}"; do
  [ -e "$t" ] || continue
  ran=$((ran + 1)); n=$(basename "$t"); out=$(bash "$t" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "PASS $n"; else echo "FAIL $n"; echo "$out" | tail -15 | sed 's/^/     /'; fail=1; fi
done
[ "$ran" -gt 0 ] || { echo "FAIL no test matches the filter '${1:-}'"; fail=1; }
exit $fail
