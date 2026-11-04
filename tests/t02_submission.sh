#!/bin/bash
# submit_all.sh with a mock sbatch: dependencies, failure of a submission, dry run and ledger
cd "$HW" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/work" "$W/envs" "$W/dbs"
cat > "$W/bin/sbatch" <<'M'
#!/bin/bash
# mock: prints a job number; fails when the job file named in FAIL_JOB is submitted
n=$(( $(cat "$MOCK_COUNT" 2>/dev/null || echo 1000) + 1 )); echo $n > "$MOCK_COUNT"
echo "$n $*" >> "$MOCK_LOG"
for a in "$@"; do case "$a" in *"${FAIL_JOB:-@none@}") echo "sbatch: error: invalid account" >&2; exit 1;; esac; done
echo $n
M
chmod +x "$W/bin/sbatch"
export PATH="$W/bin:$PATH" MOCK_COUNT="$W/count" MOCK_LOG="$W/log" HW_WORK="$W/work" HW_ENVS="$W/envs" HW_DBS="$W/dbs" HW_ACCOUNT=x HW_MAIL=x@example.org HW_PREPARE_CMD=true
export LEDGER="$W/ledger.tsv"
# 1. a normal submission
bash scripts/submit_all.sh > "$W/out.txt" 2>&1 || { cat "$W/out.txt"; echo "submission failed"; exit 1; }
n=$(wc -l < "$LEDGER"); [ "$n" -ge 90 ] || { echo "ledger has only $n jobs"; exit 1; }
id() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$LEDGER"; }
dep() { awk -F'\t' -v k="$1" '$1==k{print $3}' "$LEDGER"; }
need() { case "$(dep "$1")" in *"$(id "$2")"*) ;; *) echo "job $1 does not wait for $2 (dependency: $(dep "$1"))"; exit 1;; esac; }
need trinity conv_miseq; need trinity conv_hiseq; need scr_hw2 dbindex; need scr_proc_r1 dbindex; need pacbio check_inputs; need conv_ill check_inputs
need the22_proc_r1 genbank; need tests_hw2 check_inputs; need shared_proc_r1 acc_hw2
case "$(dep summary)" in afterany*) ;; *) echo "the summary job does not use afterany"; exit 1;; esac
arg() { awk -F'\t' -v k="$1" '$1==k{print $5}' "$LEDGER"; }   # the fifth column holds the arguments of the job
case "$(arg conv_miseq)" in *RUN=SRR5086621*EXPECTED=3333452*) ;; *) echo "the ledger does not hold the arguments of conv_miseq: '$(arg conv_miseq)'"; exit 1;; esac
case "$(arg pacbio)" in *--array=0-4*) ;; *) echo "the ledger does not hold the array argument of pacbio: '$(arg pacbio)'"; exit 1;; esac
case "$(arg tests_hw2)" in *ASM=hw2*) ;; *) echo "the ledger does not hold the arguments of tests_hw2: '$(arg tests_hw2)'"; exit 1;; esac
awk -F'\t' 'NF < 5 {print "ledger row without the fifth column: " $0; bad=1} END{exit bad}' "$LEDGER" || exit 1
# 2. a dry run keeps an existing ledger
cp "$LEDGER" "$W/ledger.before"; DRYRUN=1 bash scripts/submit_all.sh > "$W/dry.txt" 2>&1 || { echo "dry run failed"; exit 1; }
cmp -s "$LEDGER" "$W/ledger.before" || { echo "the dry run changed the ledger"; exit 1; }
# 3. a refused submission stops the script with an error
rm -f "$MOCK_COUNT"; FAIL_JOB=09_summary.sbatch bash scripts/submit_all.sh > "$W/fail.txt" 2>&1 && { echo "a failed sbatch was not noticed"; exit 1; }
grep -q 'sbatch failed' "$W/fail.txt" || { echo "no error message for the failed submission"; cat "$W/fail.txt"; exit 1; }
rm -f "$MOCK_COUNT"; FAIL_JOB=02_screen_db_index.sbatch bash scripts/submit_all.sh > "$W/fail2.txt" 2>&1 && { echo "a failed sbatch (dbindex) was not noticed"; exit 1; }
exit 0
