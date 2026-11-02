#!/bin/bash
# the checksum list of the input files: no git-lfs files (they are not downloaded), no duplicates
cd "$HW/input" 2>/dev/null || cd "$HW" || exit 1; f=CHECKSUMS.md5; [ -s "$f" ] || { echo "no $f"; exit 1; }
n=$(grep -c 'RNAseq/coverage/Sample_' "$f"); [ "$n" = 0 ] || { echo "$n git-lfs files are in the list"; exit 1; }
d=$(awk '{print $2}' "$f" | sort | uniq -d | head -1); [ -z "$d" ] || { echo "duplicate entry: $d"; exit 1; }
[ "$(wc -l < "$f")" = 647 ] || { echo "the list has $(wc -l < "$f") entries (expected 647)"; exit 1; }
grep -q 'GIT_LFS_SKIP_SMUDGE=1' "$HW/jobs/01_fetch_inputs.sbatch" || { echo "git-lfs files are not skipped by the download job"; exit 1; }
