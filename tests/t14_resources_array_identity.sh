#!/bin/bash
# t14: 09_resources.py requires exactly the tasks that the array of the job declares (in the ledger line or in the #SBATCH --array header of the job file):
# a missing task, a task that is not in the array and the allocation row of the job itself instead of a task each make it refuse the table.
set -uo pipefail
HW="${HW:?set HW to the repository root}"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"
printf '#!/bin/bash\n#SBATCH --array=0-2%%2\n' > "$W/hw/jobs/h.sbatch"; printf '#!/bin/bash\n' > "$W/hw/jobs/n.sbatch"
printf 'arr\t7001\t\th.sbatch\t\nplain\t7002\t\tn.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"
cat > "$W/bin/sacct" <<'M'
#!/bin/bash
row() { echo "$1|$2|COMPLETED|01:00:00|02:00:00|4|"; }
case "$CASE" in
  ok)        row 7001_0 7011; row 7001_1 7012; row 7001_2 7013 ;;
  missing)   row 7001_0 7011; row 7001_2 7013 ;;
  extra)     row 7001_0 7011; row 7001_1 7012; row 7001_2 7013; row 7001_7 7017 ;;
  wrong)     row 7001_0 7011; row 7001_1 7012; row 7001_9 7019 ;;
  rootrow)   row 7001 7001; row 7001_0 7011; row 7001_1 7012 ;;
esac
row 7002 7002
M
chmod +x "$W/bin/sacct"
fail=0
for c in ok missing extra wrong rootrow; do
  rm -rf "$W/hw/results/09_summary"
  CASE=$c PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/$c.out" 2>&1; rc=$?
  if [ $c = ok ]; then [ $rc = 0 ] && [ -s "$W/hw/results/09_summary/resources_totals.json" ] || { echo "FAIL: the complete array was refused: $(cat "$W/$c.out")"; fail=1; }
  else [ $rc != 0 ] && [ ! -e "$W/hw/results/09_summary/resources_totals.json" ] || { echo "FAIL: case $c was accepted"; fail=1; }; fi
done
# the array of the ledger line replaces the header
printf 'arr\t7001\t\th.sbatch\t--array=0-1\nplain\t7002\t\tn.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"
rm -rf "$W/hw/results/09_summary"; CASE=ok PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > /dev/null 2>&1 && { echo "FAIL: the array 0-1 of the ledger line was not used"; fail=1; }
[ $fail = 0 ] && echo ok
exit $fail
