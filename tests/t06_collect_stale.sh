#!/bin/bash
# the file of a step that failed (left by an earlier attempt) is not used by 06_collect.py
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
echo '{"all": {"total_bp": 5}}' > "$W/contiguity.json"; echo '{"mean": 7}' > "$W/depth.json"
python3 "$HW/scripts/06_collect.py" "$W" test reads.fq RUN1 "depth" > /dev/null 2>&1 || { echo "06_collect.py failed"; exit 1; }
python3 - "$W/summary.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s['depth'] is None, 'the old depth.json was used'
assert s['contiguity'] is not None, 'a good result was dropped'
assert s['steps_failed'] == ['depth'], s['steps_failed']
PY
