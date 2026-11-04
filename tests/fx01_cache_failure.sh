#!/bin/bash
# Offline regression test; HW is the repository under test. No writes to HW.
set -u
: "${HW:?set HW to the repository root}"
export FX_HW="$(cd "$HW" && pwd)"
export FX_W="$(mktemp -d)"
trap 'rm -rf "$FX_W"' EXIT
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1
PYTHONPATH="$TEST_DIR" PYTHONSAFEPATH= python3 -S "$TEST_DIR/cases.py" fx01
