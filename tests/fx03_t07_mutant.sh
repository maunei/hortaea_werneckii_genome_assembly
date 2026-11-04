#!/bin/bash
# FX-03 (t07): tests/t07_resources.sh must fail for a mutant of 09_resources.py that always says COMPLETED.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# 1. Baseline: t07_resources.sh must pass on the unmodified repository
HW="$HW" bash "$HW/tests/t07_resources.sh" > "$W/base.out" 2>&1 || {
  echo "baseline t07_resources.sh failed on unmodified repo:"
  cat "$W/base.out"
  exit 1
}

# 2. Mutant: copy scripts/09_resources.py and force every job's state assignment to 'COMPLETED'
mkdir -p "$W/repo/scripts"
python3 - "$HW/scripts/09_resources.py" "$W/repo/scripts/09_resources.py" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
txt = open(src).read()
mut, n = re.subn(r"(?m)^(\s*)j\['state'\]\s*=\s*(?!=).*", r"\1j['state'] = 'COMPLETED'", txt)
assert n >= 1, "could not locate j['state'] = ... assignment in 09_resources.py"
compile(mut, dst, 'exec')
open(dst, 'w').write(mut)
PY

if HW="$W/repo" bash "$HW/tests/t07_resources.sh" > "$W/mut.out" 2>&1; then
  echo "FAIL: tests/t07_resources.sh passed on a mutant of 09_resources.py that always sets state=COMPLETED"
  exit 1
fi
exit 0
