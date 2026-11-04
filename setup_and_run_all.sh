#!/bin/bash
# Sets up the Hw 2.1 workflow from the values in settings.yaml and runs the whole analysis.
#   bash setup_and_run_all.sh STAGE [settings-file]
# STAGE is one of
#   settings    check settings.yaml and write config/local.sh (the values that the jobs read); makes the folders
#   software    create the ten software environments in envs_dir (skips the ones that exist; needs micromamba or conda and internet)
#   databases   download and index the reference databases into dbs_dir (skipped when they are already there)
#   inputs      download the input files into input/, or link them from input_source (skipped when all files are there)
#   check       check the folders, programs, databases and input files, run a one-minute job that tests them from a compute node, and print the dry run
#   run         submit the whole analysis (scripts/submit_all.sh) and one short job that sends a message when everything has finished
#   all         settings, software, databases, inputs, check, run (stops at the first problem; can be repeated)
# DRYRUN=1 bash setup_and_run_all.sh run     prints the submissions only.
HW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$HW" || exit 1
STAGE="${1:-help}"; SETTINGS="${2:-$HW/settings.yaml}"
die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo; echo "=== $*"; }
sbatch_id() {   # sbatch_id ARGS: submits a job and prints its number; fails (with the message of sbatch) when the job was not accepted
  local out; out=$(sbatch --parsable "$@") || return 1; out="${out%%;*}"; [[ "$out" =~ ^[0-9]+$ ]] || return 1; echo "$out"
}
yget() { awk -F: -v k="$1" '$1 == k { sub(/^[^:]*:[ \t]*/, ""); v = $0;   # a quoted value is read up to its closing quote (a # inside it is part of the value); an unquoted value ends at " #"
    if (match(v, /^"[^"]*"/) || match(v, /^\047[^\047]*\047/)) { q = substr(v, 2, RLENGTH - 2); if (substr(v, RLENGTH + 1) ~ /^[ \t]*(#.*)?$/) v = q }   # text after the closing quote that is not a comment (an escaped quote, for example): the whole text is kept, with its quotes, and the check of the settings refuses it
    else { sub(/(^|[ \t]+)#.*$/, "", v); sub(/[ \t]+$/, "", v) }
    print v; exit }' "$SETTINGS"; }

stage_settings() {
  say "settings: $SETTINGS"
  [ -f "$SETTINGS" ] || die "settings file not found: $SETTINGS"
  local k v
  for k in account work_dir envs_dir dbs_dir; do v="$(yget $k)"; [ -n "$v" ] || die "settings.yaml: '$k' is empty"; done
  MAIL_WHEN="$(yget mail_when)"; MAIL_WHEN="${MAIL_WHEN:-FAIL}"
  case "$MAIL_WHEN" in FAIL|ALL|NONE) ;; *) die "settings.yaml: mail_when must be FAIL, ALL or NONE (it is '$MAIL_WHEN')";; esac
  MAIL="$(yget mail_address)"
  [ "$MAIL_WHEN" = NONE ] || { [ -n "$MAIL" ] && [[ "$MAIL" != *example.org ]] || die "settings.yaml: set mail_address (or mail_when: NONE)"; }
  [[ "$(yget account)" != *yourgroup* ]] || die "settings.yaml: set account"
  for k in work_dir envs_dir dbs_dir; do [[ "$(yget $k)" != /path/to* ]] || die "settings.yaml: set $k"; [[ "$(yget $k)" = /* ]] || die "settings.yaml: $k must be an absolute path"; done
  for k in account mail_address modules finished_job_name mail_when; do v="$(yget $k)"; [[ "$v" != *[\"\'\\\`\$]* ]] || die "settings.yaml: $k holds a quote, a backslash, a backtick or a dollar sign: $v"; done
  for k in work_dir envs_dir dbs_dir input_source; do v="$(yget $k)"; [ -z "$v" ] || [[ "$v" =~ ^[A-Za-z0-9_./+=@:%-]+$ ]] || die "settings.yaml: $k holds a character that the scripts do not handle (a space, a quote, a backslash or another special character): $v"; done
  INPUT_SOURCE="$(yget input_source)"; [ -z "$INPUT_SOURCE" ] || [[ "$INPUT_SOURCE" = /* ]] || die "settings.yaml: input_source must be an absolute path"
  [ -z "$INPUT_SOURCE" ] || [ -d "$INPUT_SOURCE" ] || die "settings.yaml: input_source is not a folder: $INPUT_SOURCE"
  mkdir -p "$(yget work_dir)" "$(yget envs_dir)" "$(yget dbs_dir)" || die "cannot create the folders of settings.yaml"
  {
    echo "# Written by setup_and_run_all.sh from settings.yaml. Not part of the repository; do not edit."
    printf 'export HW_WORK=%q\n' "$(yget work_dir)"; printf 'export HW_ENVS=%q\n' "$(yget envs_dir)"; printf 'export HW_DBS=%q\n' "$(yget dbs_dir)"
    printf 'export HW_ACCOUNT=%q\n' "$(yget account)"; printf 'export HW_MAIL=%q\n' "$MAIL"; printf 'export HW_MAIL_WHEN=%q\n' "$MAIL_WHEN"
    printf 'export HW_MODULES=%q\n' "$(yget modules)"; printf 'export HW_FINISHED_JOB=%q\n' "$(yget finished_job_name)"
  } > config/local.sh
  echo "account $(yget account) | mail: $MAIL_WHEN | work $(yget work_dir) | environments $(yget envs_dir) | databases $(yget dbs_dir)"
  echo "written: config/local.sh"
}
load() { [ -f config/local.sh ] || die "config/local.sh does not exist: run  bash setup_and_run_all.sh settings"; unset HW RESULTS WORK ENVS DBS INPUT LOGS_BASE; source config/config.sh; INPUT_SOURCE="$(yget input_source)"; }
squeue_wait() {   # squeue_wait "id[,id...]": polls until jobs leave queue; tolerates transient slurmctld errors
  local ids="$1" out rc
  while true; do
    out="$(squeue -h -j "$ids" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then [ -n "$out" ] || break
    elif [[ "$out" == *"Invalid job id"* ]]; then break
    else echo "WARN: squeue transient error ($out); retrying in 30 s" >&2
    fi
    sleep 30
  done
  sleep 5
}
wait_jobs() {   # wait_jobs "id,id" "label": waits until the jobs have left the queue, then stops unless the accounting holds every job and all of them completed
  local ids="$1" label="$2" rows bad i
  echo "waiting for $label (job $ids); checks every 30 s"
  squeue_wait "$ids"
  rows="$(sacct -j "$ids" -X -n -P -o JobID,JobName,State,ExitCode)" || die "sacct failed for $label (job $ids): the accounting is not available"
  [ -n "$rows" ] || die "sacct returned no accounting records for $label (job $ids)"
  for i in ${ids//,/ }; do printf '%s\n' "$rows" | cut -d'|' -f1 | grep -qE "^${i}(_|\$)" || die "the accounting has no record of job $i ($label)"; done
  bad="$(printf '%s\n' "$rows" | grep -v '|COMPLETED|' || true)"
  [ -z "$bad" ] || { echo "$bad"; die "$label did not complete; read the log in logs/ (job name and number above)"; }
  echo "$label completed"
}

job_state() {   # job_state ID: waits until the job has left the queue and prints its final state (COMPLETED, TIMEOUT, FAILED, ...)
  local id="$1" st
  squeue_wait "$id"
  st="$(sacct -j "$id" -X -n -P -o State | head -1 | awk '{print $1}')"
  echo "${st:-UNKNOWN}"
}
work_has_old_run() {   # the work folder holds the products of an earlier run while results/ of this clone is empty: the steps would be skipped as "already done" and results/ would stay incomplete
  local d found=""; for d in asm reads pacbio_bam tests; do [ -n "$(ls -A "$WORK/$d" 2>/dev/null)" ] && found=1; done
  [ -n "$found" ] && [ -z "$(find "$RESULTS" -type f ! -name .gitkeep 2>/dev/null | head -1)" ]
}
no_old_work() {
  work_has_old_run && die "work_dir ($WORK) already holds the files of an earlier run, but results/ of this clone is empty. The steps would be skipped as 'already done' and results/ would stay incomplete. Use a new, empty folder as work_dir in settings.yaml (then run the stage settings again)."
  return 0
}
my_job() {   # my_job NAME: number of a job of that name that is queued or running and was submitted from this folder (empty when there is none): a stage that is started again waits for it instead of submitting a second one
  local id wd here rows; here=$(readlink -f "$PWD")
  rows=$(squeue -u "$USER" -h -n "$1" -t PD,R,CF -o "%i %Z" 2>&1) || die "cannot query the Slurm queue for $1: $rows"
  printf '%s\n' "$rows" | while read -r id wd; do [ -n "$id" ] && [ "$(readlink -f "$wd")" = "$here" ] && { echo "$id"; break; }; done
}
stage_software() {
  say "software: environments in $ENVS"
  if CHECK=1 bash scripts/make_environments.sh > /dev/null 2>&1; then echo "all ten environments are complete: nothing to do"; return; fi
  mkdir -p logs
  local s st attempt   # the installation (about 2 h 15 min) is a job; a job that reaches its time limit is submitted again (complete environments are kept), up to 3 times
  for attempt in 1 2 3; do
    s=$(my_job hw_01_software)
    if [ -n "$s" ]; then echo "attempt $attempt: installation job $s is already queued or running (started earlier); waiting for it"
    else
      s=$(sbatch_id "${SBATCH_COMMON[@]}" jobs/01_software.sbatch) || die "could not submit the installation of the software"
      echo "attempt $attempt: installation job $s; waiting (checks every 30 s)"
    fi
    st=$(job_state "$s")
    [ "$st" = COMPLETED ] && break
    [ "$st" = TIMEOUT ] || die "the installation of the software ended with state $st; read the log in logs/ (job $s)"
    echo "the installation job reached its time limit; it is submitted again"
  done
  [ "$st" = COMPLETED ] || die "the software is not complete after 3 attempts"
  echo "software done"
}
stage_databases() {
  say "databases: $DBS"
  local n; n=$(ls "$SCREEN_DB"/*.mmi 2>/dev/null | wc -l)
  if [ -d "$BUSCO_LINEAGE" ] && [ -s "$SWISSPROT_FUNGI" ] && [ "$n" -ge 4 ] \
     && [ -s "$DBS/mito_refs/mito_proteins.faa" ] && [ -s "$DBS/rdna_refs/vector_marker_bla.faa" ]; then echo "already present (BUSCO lineage, Swiss-Prot fungal proteins, $n screen indexes, mitochondrial and rDNA references): nothing to do"; return; fi
  # the downloads can resume (finished files are kept), so a job that reaches its time limit on a slow network is submitted again, up to 5 times
  local f i attempt st
  for attempt in 1 2 3 4 5; do
    f=$(my_job hw_fetch_databases); i=""
    if [ -n "$f" ]; then i=$(my_job hw_screen_dbindex); echo "attempt $attempt: download job $f is already queued or running (started earlier); waiting for it"
    else f=$(sbatch_id "${SBATCH_COMMON[@]}" jobs/02_fetch_databases.sbatch) || die "could not submit the download"; fi
    [ -n "$i" ] || i=$(sbatch_id --dependency=afterok:$f "${SBATCH_COMMON[@]}" jobs/02_screen_db_index.sbatch) || die "could not submit the index job"
    echo "attempt $attempt: download job $f, index job $i; waiting (checks every 30 s)"
    st=$(job_state "$f")
    if [ "$st" = COMPLETED ]; then wait_jobs "$i" "the index of the databases"; return; fi
    scancel "$i" 2>/dev/null
    [ "$st" = TIMEOUT ] || die "the download of the databases ended with state $st; read the log in logs/ (job $f)"
    echo "the download job reached its time limit; it is submitted again and continues with the files that are missing"
  done
  die "the databases are not complete after 5 attempts; run the stage databases again"
}
inputs_missing() { ( cd "$INPUT" && { awk '{print $2}' CHECKSUMS.md5; awk -F'\t' 'NR>1 && $1 != "" {print "pacbio_deposited/" $1 "/" $2}' manifests/pacbio_deposited_fastq.tsv; } | while read -r f; do [ -e "$f" ] || echo "$f"; done | head -1 ); }   # the files of CHECKSUMS.md5 and the file deposited by the authors (manifests/pacbio_deposited_fastq.tsv)
stage_inputs() {
  say "inputs: $INPUT"
  if [ -n "$INPUT_SOURCE" ]; then
    echo "linking the files of $INPUT_SOURCE into input/ (the files that the repository holds are kept)"
    ( cd "$INPUT_SOURCE" && find . -type f ! -name '*.part' ! -name 'fetch_report.tsv' ! -name '.fetch.lock' ) | while read -r f; do f=${f#./}; [ -e "$INPUT/$f" ] || { mkdir -p "$INPUT/$(dirname "$f")"; ln -s "$INPUT_SOURCE/$f" "$INPUT/$f"; }; done
    echo "links: $(find "$INPUT" -type l | wc -l)"
  fi
  local m; for m in pacbio_files rna_sra_files illumina2013_sra_files pacbio_deposited_fastq; do [ -s "$INPUT/manifests/$m.tsv" ] || die "the manifest $INPUT/manifests/$m.tsv is missing or empty"; done
  if [ -z "$(inputs_missing)" ]; then echo "all files of input/CHECKSUMS.md5 are present: nothing to download"; return; fi
  [ -z "$INPUT_SOURCE" ] || die "input_source does not hold every file of input/CHECKSUMS.md5 (first missing: $(inputs_missing))"
  local f attempt st   # a job that reaches its time limit on a slow network is submitted again (finished files are kept), up to 5 times
  for attempt in 1 2 3 4 5; do
    f=$(my_job hw_01_fetch_inputs)
    if [ -n "$f" ]; then echo "attempt $attempt: download job $f is already queued or running (started earlier); waiting for it"
    else
      f=$(sbatch_id "${SBATCH_COMMON[@]}" jobs/01_fetch_inputs.sbatch) || die "could not submit the download"
      echo "attempt $attempt: download job $f; waiting (checks every 30 s)"
    fi
    st=$(job_state "$f")
    [ "$st" = COMPLETED ] && break
    [ "$st" = TIMEOUT ] || die "the download of the input files ended with state $st; read the log in logs/ (job $f)"
    echo "the download job reached its time limit; it is submitted again and continues with the files that are missing"
  done
  [ -z "$(inputs_missing)" ] || die "files are still missing after the download (first: $(inputs_missing))"
}
stage_check() {
  say "check"
  no_old_work
  [ -z "$(inputs_missing)" ] || die "input files are missing (first: $(inputs_missing)); run the stage inputs"
  echo "input files: all present"
  local p; p=$(sbatch_id "${SBATCH_COMMON[@]}" jobs/00_preflight.sbatch) || die "could not submit the check job"
  wait_jobs "$p" "the check job (programs, databases and folders seen from a compute node)"
  grep -h "MISSING\|PREFLIGHT\|versions:" logs/hw_00_preflight_$p.out
  say "dry run of the whole analysis"
  DRYRUN=1 bash scripts/submit_all.sh > logs/dryrun.txt && echo "submissions that the run will make: $(grep -c sbatch logs/dryrun.txt) (list in logs/dryrun.txt)"
}
expected_rows() {   # expected_rows LEDGER: the number of accounting rows of the jobs of the ledger: 1 per job, one per task of an array (the array is given in the ledger or in the header of the job file)
  awk -F'\t' -v dir="${HW:-.}/jobs" 'function cnt(spec,  n,i,a,m,b,s,k){ gsub(/%[0-9]+/,"",spec); n=0; m=split(spec,a,","); for(i=1;i<=m;i++){ if (a[i] ~ /^[0-9]+-[0-9]+(:[0-9]+)?$/) { split(a[i],b,/[-:]/); s=(b[3]?b[3]:1); for(k=b[1];k<=b[2];k+=s) n++ } else if (a[i] ~ /^[0-9]+$/) n++ } return n }
    { spec=""; if (match($5,/--array[= ][^ ]+/)) { spec=substr($5,RSTART,RLENGTH); sub(/--array[= ]/,"",spec) } else { f=dir "/" $4; while ((getline line < f) > 0) if (line ~ /^#SBATCH[ \t]+--array=/) { spec=line; sub(/^.*--array=/,"",spec); sub(/[ \t].*$/,"",spec); break } close(f) }
      c = (spec != "") ? cnt(spec) : 1; if (c < 1) c = 1; total += c } END { print total + 0 }' "$1"
}
final_cmd() {   # final_cmd LEDGER: the command of the message job; FAILED unless the accounting holds every job (and every task of an array) of the ledger and all are COMPLETED
  local led="$1" ids idl n cmd; ids=$(awk '{print $2}' "$led" | paste -sd, -); idl=$(awk '{print $2}' "$led" | paste -sd' ' -); n=$(expected_rows "$led")   # n: the rows that the accounting must hold (one per job, one per task of an array)
  cmd='sleep 20; st=$(sacct -j IDS -X -n -P -o JobID,State) || exit 1; n=$(printf "%s\n" "$st" | grep -c .); [ "$n" -ge NN ] || exit 1; for i in IDLIST; do printf "%s\n" "$st" | grep -q "^$i[_|]" || exit 1; done; ! printf "%s\n" "$st" | grep -qv "|COMPLETED$"'
  cmd=${cmd//IDS/$ids}; cmd=${cmd//NN/$n}; cmd=${cmd//IDLIST/$idl}; printf '%s\n' "$cmd"
}
stage_run() {
  say "run"
  [ -n "$DRYRUN" ] || no_old_work
  [ -n "$DRYRUN" ] || { local q; q=$(my_job hw_09_summary); [ -z "$q" ] || die "the analysis is already submitted from this folder (summary job $q is waiting in the queue); wait for it, and follow it with: squeue -u \$USER"; }
  local led="${LEDGER:-jobs/submitted_by_submit_all.tsv}"; export LEDGER="$led"   # one ledger for this run: the submission, the cancellation, the summary lookup and the message job all use it
  if [ -n "$DRYRUN" ]; then DRYRUN=1 bash scripts/submit_all.sh > logs/dryrun.txt 2>&1 || { tail -3 logs/dryrun.txt; die "the dry run failed"; }; tail -3 logs/dryrun.txt; return; fi
  local submission_lock_fd
  exec {submission_lock_fd}>> "$HW/jobs/.submission.lock" || die "cannot open the submission lock; no submission attempted"
  flock -n "$submission_lock_fd" || die "another submission from this folder is still in progress; no submission attempted"
  if [ -s "$led" ]; then local old_ids still queue_rows; old_ids=$(awk '$2 ~ /^[0-9]+$/ {print $2}' "$led" | paste -sd, -)   # jobs of an earlier attempt (for example a submission that was interrupted) that are still queued or running: they would run twice
    still=""
    if [ -n "$old_ids" ]; then
      queue_rows=$(squeue -h -u "$USER" -o "%i" 2>&1) || die "cannot verify the previous attempt in the queue; ledger preserved: $queue_rows"
      still=$(printf '%s\n' "$queue_rows" | awk -v ids="$old_ids" 'BEGIN { n=split(ids,a,","); for(i=1;i<=n;i++) wanted[a[i]]=1 } { id=$1; sub(/_.*/,"",id); if(id in wanted) {print; if(++seen==3) exit} }' | paste -sd' ' -)
    fi
    [ -z "$still" ] || die "jobs of an earlier attempt are still in the queue (for example $still; the list is in $led): cancel them with  scancel $(echo "$old_ids" | tr , ' ')  or wait for them, and run the stage run again"; fi
  mkdir -p "$(dirname "$led")" || die "cannot create the ledger folder; no submission attempted"
  : > "$led" || die "cannot initialize the attempt ledger; no submission or cancellation attempted"   # an empty ledger for this attempt: a ledger of an earlier attempt is never read
  if ! bash scripts/submit_all.sh > logs/submit_all.txt 2>&1; then   # a submission that stopped half way: the jobs already accepted (the ledger of this attempt) are cancelled, so that no partial analysis runs
    tail -5 logs/submit_all.txt; awk '$2 ~ /^[0-9]+$/ {print $2}' "$led" | xargs -r scancel || echo "WARNING: scancel reported an error; check with squeue -u \$USER" >&2
    die "the submission of the analysis stopped (see above); the jobs already submitted were cancelled; correct the problem and run the stage run again"
  fi
  tail -2 logs/submit_all.txt
  local s; s=$(awk '$1=="summary"{print $2}' "$led"); [ -n "$s" ] || die "the summary job was not submitted"
  echo "all jobs are submitted; the last job (09_summary, job $s) runs when all others have ended"
  if [ "${HW_MAIL_WHEN:-FAIL}" != NONE ]; then
    # runs when the summary job has ended; ends with an error when any job of the analysis (all jobs of jobs/submitted_by_submit_all.tsv, the summary included) did not complete,
    # so that the scheduler message says "COMPLETED" or "FAILED"
    local cmd; cmd=$(final_cmd "$led")
    sbatch --parsable -J "${HW_FINISHED_JOB:-hw_run_finished}" --dependency=afterany:$s --account="$HW_ACCOUNT" --mail-type=BEGIN,END --mail-user="$HW_MAIL" \
           --time=00:02:00 --mem=100M --cpus-per-task=1 --output=/dev/null --wrap="$cmd" > /dev/null \
      && echo "one message will be sent when the summary job has ended (job name ${HW_FINISHED_JOB:-hw_run_finished}): 'COMPLETED' if all jobs of the analysis completed, 'FAILED' if any job failed or was cancelled; a failed job is also reported by the scheduler"
  fi
  echo "follow the run with:  squeue -u \$USER;  results will be in results/ (README, 'Run everything')"
}

case "$STAGE" in
  settings)  stage_settings ;;
  software)  load; stage_software ;;
  databases) load; stage_databases ;;
  inputs)    load; stage_inputs ;;
  check)     load; stage_check ;;
  run)       load; stage_run ;;
  all)       stage_settings; load; stage_software; stage_databases; stage_inputs; stage_check; stage_run ;;
  *) echo "Nothing was run: no stage was given. Usage:  bash setup_and_run_all.sh STAGE   (all = everything, in order)"; echo; sed -n '2,12p' "$0"; exit 0 ;;
esac
