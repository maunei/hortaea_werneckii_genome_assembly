#!/bin/bash
# the example submission lines of the README are the lines that DRYRUN=1 bash scripts/submit_all.sh prints now (the README holds a copy)
[ -s "$HW/README.md" ] || { echo "skipped (no README.md)"; exit 0; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
HW_WORK='$WORK' HW_ENVS="$W/e" HW_DBS="$W/d" DRYRUN=1 bash "$HW/scripts/submit_all.sh" > "$W/actual.txt" 2>&1 || { echo "DRYRUN=1 submit_all.sh failed"; cat "$W/actual.txt" | tail -3; exit 1; }
# sbatch lines of the README block, as printed by the script (every line that starts with sbatch)
# the README prints the lines broken with a backslash at the end of a line (they are joined here), and names the jobs that the summary waits for as one group, <all_other_jobs>
grep '^sbatch' "$W/actual.txt" | sed 's/afterany:\(<[^>]*>:\?\)\+/afterany:<all_other_jobs>/' | sed 's/[[:space:]]\+/ /g' | sort > "$W/a.txt"
sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}' "$HW/README.md" | sed 's/[[:space:]]\+/ /g' | grep '^sbatch --dependency=after\(ok\|any\):<\|^sbatch --\(array\|export\)\|^sbatch jobs/' | sort -u > "$W/r_all.txt"
missing=$(comm -23 "$W/a.txt" "$W/r_all.txt" | head -3)
[ -z "$missing" ] || { echo "lines of the dry run that are not in the README:"; echo "$missing"; exit 1; }
[ "$(wc -l < "$W/a.txt")" -ge 90 ] || { echo "the dry run printed only $(wc -l < "$W/a.txt") sbatch lines"; exit 1; }
