#!/bin/bash
# Runs the tests of this folder (see README.md). Usage: bash tests/run_tests.sh [prefix]
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export HW="$(cd "$T/.." && pwd)"; fail=0
for t in "$T"/t${1:-}*.sh; do
  n=$(basename "$t"); out=$(bash "$t" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "PASS $n"; else echo "FAIL $n"; echo "$out" | tail -15 | sed 's/^/     /'; fail=1; fi
done
exit $fail
