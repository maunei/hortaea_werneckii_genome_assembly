#!/bin/bash
# every shell script and job file passes bash -n; every Python script compiles
cd "$HW" || exit 1; bad=0
for f in setup_and_run_all.sh scripts/*.sh jobs/*.sbatch config/*.sh tests/*.sh; do bash -n "$f" || { echo "syntax error: $f"; bad=1; }; done
for f in scripts/*.py; do python3 - "$f" <<'PY' || { echo "does not compile: $f"; bad=1; }
import sys; compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')
PY
done
exit $bad
