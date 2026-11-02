#!/bin/bash
# the function step() of jobs/06_tests.sbatch: a command that fails in the middle of a step makes the step fail
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; BIG="$W"; mkdir -p "$BIG/steps"; FAILED=""; FORCE=0
eval "$(sed -n '/^step() {/,/^}/p' "$HW/jobs/06_tests.sbatch")"
s_bad() { false; echo "later command that succeeds"; }
s_good() { true; }
step bad s_bad > /dev/null; step good s_good > /dev/null
[ "${FAILED# }" = bad ] || { echo "failed steps: '$FAILED' (expected: bad)"; exit 1; }
[ ! -e "$BIG/steps/bad.done" ] && [ -e "$BIG/steps/good.done" ] || { echo "markers wrong"; exit 1; }
