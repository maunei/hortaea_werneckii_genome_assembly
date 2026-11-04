#!/bin/bash
# FX-40: (a) 09_resources.py task_numbers identity check (exact task numbers from #SBATCH --array header
# or ledger override; refuses wrong task number, allocation row instead of task, or extra task)
# and setup_and_run_all.sh final_cmd / expected_rows (every job identity, counts, prefix collisions, CWD != HW).
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# Part 1: 09_resources.py task_numbers exact set check
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"
printf '#!/bin/bash\n#SBATCH --array=0-2%%2\n' > "$W/hw/jobs/h.sbatch"
printf '#!/bin/bash\n#SBATCH -J plain\n' > "$W/hw/jobs/n.sbatch"
printf 'arr\t7001\t\th.sbatch\t\nplain\t7002\t\tn.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"

cat > "$W/bin/sacct" <<'EOF'
#!/bin/bash
row() { echo "$1|$2|COMPLETED|01:00:00|02:00:00|4|"; }
case "${CASE:-}" in
  ok)      row 7001_0 7011; row 7001_1 7012; row 7001_2 7013 ;;
  missing) row 7001_0 7011; row 7001_2 7013 ;;
  wrong)   row 7001_0 7011; row 7001_1 7012; row 7001_9 7019 ;;
  rootrow) row 7001 7001; row 7001_0 7011; row 7001_1 7012 ;;
  extra)   row 7001_0 7011; row 7001_1 7012; row 7001_2 7013; row 7001_7 7017 ;;
esac
row 7002 7002
EOF
chmod +x "$W/bin/sacct"

for c in ok missing wrong rootrow extra; do
  rm -rf "$W/hw/results/09_summary"
  rc=0
  CASE="$c" PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/res_$c.out" 2>&1 || rc=$?
  if [ "$c" = "ok" ]; then
    [ "$rc" -eq 0 ] && [ -s "$W/hw/results/09_summary/resources_totals.json" ] || {
      echo "FAIL: 09_resources.py rejected valid array tasks (case ok, rc=$rc)" >&2
      cat "$W/res_$c.out" >&2
      exit 1
    }
  else
    [ "$rc" -ne 0 ] && [ ! -e "$W/hw/results/09_summary/resources_totals.json" ] || {
      echo "FAIL: 09_resources.py accepted invalid array tasks (case $c, rc=$rc)" >&2
      cat "$W/res_$c.out" >&2
      exit 1
    }
  fi
done

# Ledger array specification overrides #SBATCH --array header
printf 'arr\t7001\t\th.sbatch\t--array=0-1\nplain\t7002\t\tn.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"
rm -rf "$W/hw/results/09_summary"
if CASE=ok PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/res_override.out" 2>&1; then
  echo "FAIL: 09_resources.py did not use ledger --array=0-1 override over header 0-2" >&2
  exit 1
fi

# Part 2: expected_rows (with CWD != HW) and final_cmd in setup_and_run_all.sh
FnDefs="$W/fn.sh"
sed -n '/^expected_rows()/,/^}/p; /^final_cmd()/,/^}/p' "$HW/setup_and_run_all.sh" > "$FnDefs"
grep -q '^final_cmd()' "$FnDefs" || { echo "FAIL: final_cmd() not found in setup_and_run_all.sh" >&2; exit 1; }
# shellcheck disable=SC1090
source "$FnDefs"

printf 'first\t11\t\th.sbatch\t\nsecond\t12\t\tn.sbatch\t\nlast\t13\t\tn.sbatch\t\n' > "$W/led"
got_rows="$(cd / && HW="$W/hw" expected_rows "$W/led")"
[ "$got_rows" = "5" ] || { echo "FAIL: expected_rows from / returned '$got_rows' (expected 5)" >&2; exit 1; }

cmd="$(cd / && HW="$W/hw" final_cmd "$W/led")"
grep -q 'ge 5 ' <<<"$cmd" || { echo "FAIL: final_cmd did not embed expected row count 5: $cmd" >&2; exit 1; }

printf '#!/bin/bash\nexit 0\n' > "$W/bin/sleep"
chmod +x "$W/bin/sleep"
cat > "$W/bin/sacct" <<'EOF'
#!/bin/bash
t3() { for k in 0 1 2; do echo "11_$k|${1:-COMPLETED}"; done; }
case "${CASE:-}" in
  full)         t3; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  no_first)     for k in 0 1 2; do echo "111_$k|COMPLETED"; done; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  no_middle)    t3; echo "13|COMPLETED"; echo "13|COMPLETED" ;;
  no_last)      t3; echo "12|COMPLETED"; echo "12|COMPLETED" ;;
  prefix_last)  t3; echo "12|COMPLETED"; echo "130|COMPLETED" ;;
  short_array)  echo "11_0|COMPLETED"; echo "11_1|COMPLETED"; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  task_failed)  echo "11_0|COMPLETED"; echo "11_1|FAILED"; echo "11_2|COMPLETED"; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
esac
EOF
chmod +x "$W/bin/sacct"

for c in full no_first no_middle no_last prefix_last short_array task_failed; do
  rc=0
  CASE="$c" PATH="$W/bin:$PATH" bash -c "$cmd" >/dev/null 2>&1 || rc=$?
  if [ "$c" = "full" ]; then
    [ "$rc" -eq 0 ] || { echo "FAIL: final_cmd failed on case full" >&2; exit 1; }
  else
    [ "$rc" -ne 0 ] || { echo "FAIL: final_cmd succeeded on broken accounting case $c" >&2; exit 1; }
  fi
done

echo "PASS"
