#!/bin/bash
# optional: HW_TEST_RESULTS=<results folder of a complete run>. The summary step runs again on a copy; the tables and verdicts must be identical.
[ -n "$HW_TEST_RESULTS" ] && [ -d "$HW_TEST_RESULTS/09_summary" ] || { echo "skipped (HW_TEST_RESULTS is not set)"; exit 0; }
PYB="${PY:-python3}"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; cp -r "$HW_TEST_RESULTS" "$W/results"
HW="$HW" RESULTS="$W/results" $PYB "$HW/scripts/09_summary.py" > /dev/null 2>&1 || { echo "09_summary.py failed"; exit 1; }
for f in measures.tsv verdict.tsv noise_scale.tsv verdict.json; do cmp -s "$HW_TEST_RESULTS/09_summary/$f" "$W/results/09_summary/$f" || { echo "$f differs"; exit 1; }; done
