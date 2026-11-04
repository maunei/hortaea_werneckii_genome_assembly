#!/bin/bash
# t12: the rows that the accounting must hold (one per job, one per task of an array), and the command of the final message job
# (final_cmd of setup_and_run_all.sh): it must not report COMPLETED when a job of the ledger has no row, an array has fewer rows than tasks,
# a job number is only the beginning of another job number, or a task did not complete.
set -uo pipefail
HW="${HW:?set HW to the repository root}"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/jobs" "$W/bin"; cd "$W"
source <(sed -n '/^expected_rows()/,/^}/p; /^final_cmd()/,/^}/p' "$HW/setup_and_run_all.sh")
fail=0; ck() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', expected '$3')"; fail=1; fi; }
printf '#!/bin/bash\n#SBATCH --array=0-3%%2\n' > jobs/h.sbatch; printf '#!/bin/bash\n#SBATCH -J x\n' > jobs/n.sbatch
printf 'a\t1\t\tn.sbatch\t\nb\t2\t\th.sbatch\t\nc\t3\t\tn.sbatch\t--array=0-4 --x=y\nd\t4\t\tn.sbatch\t--array=1,3,5\ne\t5\t\tn.sbatch\t--array=0-8:4%%1\n' > led
export HW="$W"   # the job files of the test are in $W/jobs
ck "expected rows: plain job 1 + header array 4 + ledger array 5 + list 3 + stride 3" "$(cd /; expected_rows "$W/led")" 16
# the final message job, for a ledger with an array job 11 (5 tasks), a job 12, and a job 13
printf 'first\t11\t\tn.sbatch\t--array=0-4\nsecond\t12\t\tn.sbatch\t\nlast\t13\t\tn.sbatch\t\n' > led2
cmd=$(final_cmd led2); ck "the command asks for 7 rows" "$(grep -c 'ge 7 ' <<<"$cmd")" 1
printf '#!/bin/bash\nexit 0\n' > bin/sleep
cat > bin/sacct <<'M'
#!/bin/bash
t5() { for k in 0 1 2 3 4; do echo "11_$k|${1:-COMPLETED}"; done; }
case "$CASE" in
  full)        t5; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  no_last)     t5; echo "12|COMPLETED"; echo "12|COMPLETED" ;;                                  # 7 rows, but no row of the job 13
  no_first)    for k in 0 1 2 3 4; do echo "111_$k|COMPLETED"; done; echo "12|COMPLETED"; echo "13|COMPLETED" ;;   # 7 rows, none of the job 11 (111 only starts with 11)
  no_middle)   t5; echo "13|COMPLETED"; echo "13|COMPLETED" ;;                                  # 7 rows, no row of the job 12
  short_array) echo "11_0|COMPLETED"; echo "11_1|COMPLETED"; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  prefix_last) t5; echo "12|COMPLETED"; echo "130|COMPLETED"; echo "13x|COMPLETED" ;;           # 130 is not 13
  task_failed) for k in 0 1 2; do echo "11_$k|COMPLETED"; done; echo "11_3|FAILED"; echo "11_4|COMPLETED"; echo "12|COMPLETED"; echo "13|COMPLETED" ;;
  cancelled)   t5; echo "12|COMPLETED"; echo "13|CANCELLED by 0" ;;
  fail)        echo "sacct: error" >&2; exit 1 ;;
esac
M
chmod +x bin/sleep bin/sacct
for c in full no_last no_first no_middle short_array prefix_last task_failed cancelled fail; do
  CASE=$c PATH="$W/bin:$PATH" bash -c "$cmd" >/dev/null 2>&1; rc=$?
  if [ "$c" = full ]; then ck "message job, accounting $c: success" "$rc" 0; else [ "$rc" != 0 ]; ck "message job, accounting $c: FAILED" "$?" 0; fi
done
exit $fail
