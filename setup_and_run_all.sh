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
yget() { awk -F: -v k="$1" '$1 == k { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]+#.*$/, ""); sub(/[ \t]+$/, ""); gsub(/^"|"$/, ""); gsub(/^\047|\047$/, ""); print; exit }' "$SETTINGS"; }

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
  INPUT_SOURCE="$(yget input_source)"; [ -z "$INPUT_SOURCE" ] || [ -d "$INPUT_SOURCE" ] || die "settings.yaml: input_source is not a folder: $INPUT_SOURCE"
  mkdir -p "$(yget work_dir)" "$(yget envs_dir)" "$(yget dbs_dir)" || die "cannot create the folders of settings.yaml"
  {
    echo "# Written by setup_and_run_all.sh from settings.yaml. Not part of the repository; do not edit."
    printf 'export HW_WORK="%s"\n' "$(yget work_dir)"; printf 'export HW_ENVS="%s"\n' "$(yget envs_dir)"; printf 'export HW_DBS="%s"\n' "$(yget dbs_dir)"
    printf 'export HW_ACCOUNT="%s"\n' "$(yget account)"; printf 'export HW_MAIL="%s"\n' "$MAIL"; printf 'export HW_MAIL_WHEN="%s"\n' "$MAIL_WHEN"
    printf 'export HW_MODULES="%s"\n' "$(yget modules)"; printf 'export HW_FINISHED_JOB="%s"\n' "$(yget finished_job_name)"
  } > config/local.sh
  echo "account $(yget account) | mail: $MAIL_WHEN | work $(yget work_dir) | environments $(yget envs_dir) | databases $(yget dbs_dir)"
  echo "written: config/local.sh"
}
load() { [ -f config/local.sh ] || die "config/local.sh does not exist: run  bash setup_and_run_all.sh settings"; unset HW RESULTS WORK ENVS DBS INPUT LOGS_BASE; source config/config.sh; INPUT_SOURCE="$(yget input_source)"; }
wait_jobs() {   # wait_jobs "id,id" "label": waits until the jobs have left the queue, then stops unless all of them completed
  local ids="$1" label="$2" bad
  echo "waiting for $label (job $ids); checks every 30 s"
  while squeue -h -j "$ids" 2>/dev/null | grep -q .; do sleep 30; done; sleep 5
  bad="$(sacct -j "$ids" -X -n -P -o JobID,JobName,State,ExitCode | grep -v '|COMPLETED|')"
  [ -z "$bad" ] || { echo "$bad"; die "$label did not complete; read the log in logs/ (job name and number above)"; }
  echo "$label completed"
}

job_state() {   # job_state ID: waits until the job has left the queue and prints its final state (COMPLETED, TIMEOUT, FAILED, ...)
  local id="$1"; while squeue -h -j "$id" 2>/dev/null | grep -q .; do sleep 30; done; sleep 5
  sacct -j "$id" -X -n -P -o State | head -1 | awk '{print $1}'
}
work_has_old_run() {   # the work folder holds the products of an earlier run while results/ of this clone is empty: the steps would be skipped as "already done" and results/ would stay incomplete
  local d found=""; for d in asm reads pacbio_bam tests; do [ -n "$(ls -A "$WORK/$d" 2>/dev/null)" ] && found=1; done
  [ -n "$found" ] && [ -z "$(find "$RESULTS" -type f ! -name .gitkeep 2>/dev/null | head -1)" ]
}
no_old_work() {
  work_has_old_run && die "work_dir ($WORK) already holds the files of an earlier run, but results/ of this clone is empty. The steps would be skipped as 'already done' and results/ would stay incomplete. Use a new, empty folder as work_dir in settings.yaml (then run the stage settings again)."
  return 0
}
stage_software() {
  say "software: environments in $ENVS"
  mkdir -p logs; bash scripts/make_environments.sh 2>&1 | tee logs/make_environments.txt
  grep -q "FAILED\|not found" logs/make_environments.txt && die "an environment could not be created (see above)"
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
    f=$(sbatch --parsable "${SBATCH_COMMON[@]}" jobs/02_fetch_databases.sbatch | cut -d';' -f1) || die "could not submit the download"
    i=$(sbatch --parsable --dependency=afterok:$f "${SBATCH_COMMON[@]}" jobs/02_screen_db_index.sbatch | cut -d';' -f1) || die "could not submit the index job"
    echo "attempt $attempt: download job $f, index job $i; waiting (checks every 30 s)"
    st=$(job_state "$f")
    if [ "$st" = COMPLETED ]; then wait_jobs "$i" "the index of the databases"; return; fi
    scancel "$i" 2>/dev/null
    [ "$st" = TIMEOUT ] || die "the download of the databases ended with state $st; read the log in logs/ (job $f)"
    echo "the download job reached its time limit; it is submitted again and continues with the files that are missing"
  done
  die "the databases are not complete after 5 attempts; run the stage databases again"
}
inputs_missing() { ( cd "$INPUT" && awk '{print $2}' CHECKSUMS.md5 | while read -r f; do [ -e "$f" ] || echo "$f"; done | head -1 ); }
stage_inputs() {
  say "inputs: $INPUT"
  if [ -n "$INPUT_SOURCE" ]; then
    echo "linking the files of $INPUT_SOURCE into input/ (the files that the repository holds are kept)"
    ( cd "$INPUT_SOURCE" && find . -type f ) | while read -r f; do f=${f#./}; [ -e "$INPUT/$f" ] || { mkdir -p "$INPUT/$(dirname "$f")"; ln -s "$INPUT_SOURCE/$f" "$INPUT/$f"; }; done
    echo "links: $(find "$INPUT" -type l | wc -l)"
  fi
  if [ -z "$(inputs_missing)" ]; then echo "all files of input/CHECKSUMS.md5 are present: nothing to download"; return; fi
  [ -z "$INPUT_SOURCE" ] || die "input_source does not hold every file of input/CHECKSUMS.md5 (first missing: $(inputs_missing))"
  local f attempt st   # a job that reaches its time limit on a slow network is submitted again (finished files are kept), up to 5 times
  for attempt in 1 2 3 4 5; do
    f=$(sbatch --parsable "${SBATCH_COMMON[@]}" jobs/01_fetch_inputs.sbatch | cut -d';' -f1) || die "could not submit the download"
    echo "attempt $attempt: download job $f; waiting (checks every 30 s)"
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
  local p; p=$(sbatch --parsable "${SBATCH_COMMON[@]}" jobs/00_preflight.sbatch | cut -d';' -f1) || die "could not submit the check job"
  wait_jobs "$p" "the check job (programs, databases and folders seen from a compute node)"
  grep -h "MISSING\|PREFLIGHT\|versions:" logs/hw_00_preflight_$p.out
  say "dry run of the whole analysis"
  DRYRUN=1 bash scripts/submit_all.sh > logs/dryrun.txt && echo "submissions that the run will make: $(grep -c sbatch logs/dryrun.txt) (list in logs/dryrun.txt)"
}
stage_run() {
  say "run"
  [ -n "$DRYRUN" ] || no_old_work
  if [ -n "$DRYRUN" ]; then DRYRUN=1 bash scripts/submit_all.sh | tee logs/dryrun.txt | tail -3; return; fi
  bash scripts/submit_all.sh | tee logs/submit_all.txt | tail -2
  local s; s=$(awk '$1=="summary"{print $2}' jobs/submitted_by_submit_all.tsv); [ -n "$s" ] || die "the summary job was not submitted"
  echo "all jobs are submitted; the last job (09_summary, job $s) runs when all others have finished"
  if [ "${HW_MAIL_WHEN:-FAIL}" != NONE ]; then
    # runs when the summary job has ended, whether it completed or not; ends with an error when the summary did not complete, so that the scheduler message says "COMPLETED" or "FAILED"
    sbatch --parsable -J "${HW_FINISHED_JOB:-hw_run_finished}" --dependency=afterany:$s --account="$HW_ACCOUNT" --mail-type=BEGIN,END --mail-user="$HW_MAIL" \
           --time=00:02:00 --mem=100M --cpus-per-task=1 --output=/dev/null \
           --wrap="sleep 20; st=\$(sacct -j $s -X -n -P -o State | head -1); [ \"\$st\" = COMPLETED ]" > /dev/null \
      && echo "one message will be sent when the summary job has ended (job name ${HW_FINISHED_JOB:-hw_run_finished}): 'COMPLETED' if the whole analysis finished, 'FAILED' if not; a failed job is also reported by the scheduler"
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
