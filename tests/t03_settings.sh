#!/bin/bash
# settings.yaml: empty value followed by a comment, spaces and $ in values
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/repo"; ( cd "$HW" && tar cf - setup_and_run_all.sh config scripts jobs ) | ( cd "$W/repo" && tar xf - )
cat > "$W/s.yaml" <<Y
account: def-test_cpu   # the account
mail_address: someone@institute.ca
mail_when: ALL  # all messages
modules:   # nothing to load
finished_job_name: hw_run_finished
work_dir: "$W/a dir/work\$x"   # with a space and a dollar sign
envs_dir: $W/envs
dbs_dir: $W/dbs
input_source: ""  # none
Y
( cd "$W/repo" && bash setup_and_run_all.sh settings "$W/s.yaml" > "$W/out.txt" 2>&1 ) || { cat "$W/out.txt"; exit 1; }
( source "$W/repo/config/local.sh"
  [ -z "$HW_MODULES" ] || { echo "HW_MODULES is '$HW_MODULES' instead of empty"; exit 1; }
  [ "$HW_WORK" = "$W/a dir/work\$x" ] || { echo "HW_WORK is '$HW_WORK'"; exit 1; }
  [ "$HW_ACCOUNT" = def-test_cpu ] && [ "$HW_MAIL_WHEN" = ALL ] || { echo "account or mail_when wrong"; exit 1; } )
