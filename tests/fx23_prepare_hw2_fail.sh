#!/bin/bash
# FX-23 (added from Part 1c scan): scripts/01_prepare_hw2.sh must fail non-zero when Hw2.fasta.gz is damaged/corrupted.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/repo/config" "$W/repo/scripts" "$W/repo/input/hw2/github_Hortaea_werneckii/assemblies/Hw2" "$W/work"
cp "$HW/config/config.sh" "$W/repo/config/config.sh"
cp "$HW/scripts/01_prepare_hw2.sh" "$W/repo/scripts/01_prepare_hw2.sh"

# 1. Positive check: valid gzipped FASTA succeeds
printf ">chr1\nACGT\n" | gzip > "$W/repo/input/hw2/github_Hortaea_werneckii/assemblies/Hw2/Hw2.fasta.gz"
HW="$W/repo" HW_WORK="$W/work" HW_ENVS="$W/e" HW_DBS="$W/d" bash "$W/repo/scripts/01_prepare_hw2.sh" > "$W/ok.out" 2>&1 || {
  echo "01_prepare_hw2.sh failed on valid Hw2.fasta.gz:"
  cat "$W/ok.out"
  exit 1
}
[ -s "$W/work/asm/hw2/final.fasta" ] || { echo "final.fasta not written on valid run"; exit 1; }

# 2. Corrupted gzipped file must cause 01_prepare_hw2.sh to exit non-zero
rm -rf "$W/work/asm/hw2"
printf "not-a-valid-gzip-stream\n" > "$W/repo/input/hw2/github_Hortaea_werneckii/assemblies/Hw2/Hw2.fasta.gz"
if HW="$W/repo" HW_WORK="$W/work" HW_ENVS="$W/e" HW_DBS="$W/d" bash "$W/repo/scripts/01_prepare_hw2.sh" > "$W/bad.out" 2>&1; then
  echo "FAIL: scripts/01_prepare_hw2.sh exited 0 when Hw2.fasta.gz was corrupted"
  exit 1
fi
exit 0
