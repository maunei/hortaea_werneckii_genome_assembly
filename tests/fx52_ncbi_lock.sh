#!/bin/bash
set -euo pipefail
HW=${HW:?set HW to repository under test}
W=$(mktemp -d /tmp/hw-test-e.XXXXXXXX); trap 'rm -rf "$W"' EXIT
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export FX_HW="$HW" FX_W="$W" PYTHONDONTWRITEBYTECODE=1
unset PYTHONSAFEPATH PYTHONHOME
PYTHONPATH="$D" python3 -S "$D/cases_e.py" fx52
