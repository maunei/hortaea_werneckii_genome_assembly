#!/bin/bash
# settings.yaml: empty value followed by a comment, quoted value; paths with a space, a quote or a backslash are refused
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/repo"; ( cd "$HW" && tar cf - setup_and_run_all.sh config scripts jobs ) | ( cd "$W/repo" && tar xf - )
cat > "$W/s.yaml" <<Y
account: def-test_cpu   # the account
mail_address: someone@institute.ca
mail_when: ALL  # all messages
modules:   # nothing to load
finished_job_name: hw_run_finished
work_dir: "$W/work1"   # a quoted value
envs_dir: $W/envs
dbs_dir: $W/dbs
input_source: ""  # none
Y
( cd "$W/repo" && bash setup_and_run_all.sh settings "$W/s.yaml" > "$W/out.txt" 2>&1 ) || { cat "$W/out.txt"; exit 1; }
( source "$W/repo/config/local.sh"
  [ -z "$HW_MODULES" ] || { echo "HW_MODULES is '$HW_MODULES' instead of empty"; exit 1; }
  [ "$HW_WORK" = "$W/work1" ] || { echo "HW_WORK is '$HW_WORK'"; exit 1; }
  [ "$HW_ACCOUNT" = def-test_cpu ] && [ "$HW_MAIL_WHEN" = ALL ] || { echo "account or mail_when wrong"; exit 1; } )
# values that the scripts cannot handle are refused with a message, never shortened or changed
for bad in '"/x/a dir/work"' '"/x/q\" # name"' "'/x/s'' # name'" '"/x/a"b' '/x/a;b' '/x/a,b'; do
  grep -v '^work_dir:' "$W/s.yaml" > "$W/bad.yaml"; printf 'work_dir: %s\n' "$bad" >> "$W/bad.yaml"
  if ( cd "$W/repo" && bash setup_and_run_all.sh settings "$W/bad.yaml" > "$W/bad.txt" 2>&1 ); then echo "work_dir: $bad was accepted"; exit 1; fi
  grep -q 'settings.yaml: work_dir' "$W/bad.txt" || { echo "no message for work_dir: $bad"; cat "$W/bad.txt"; exit 1; }
done
# the other values may not hold a quote, a backslash, a backtick or a dollar sign; input_source must be an absolute path
for kv in 'account: "def-x\"y"' 'mail_address: a$b@c.ca' 'finished_job_name: "x\"y"' "input_source: $W"/relative; do
  case "$kv" in input_source*) kv="input_source: relative/dir";; esac
  key=${kv%%:*}; grep -v "^$key:" "$W/s.yaml" > "$W/bad.yaml"; printf '%s\n' "$kv" >> "$W/bad.yaml"
  if ( cd "$W/repo" && bash setup_and_run_all.sh settings "$W/bad.yaml" > "$W/bad.txt" 2>&1 ); then echo "$kv was accepted"; exit 1; fi
  grep -q "settings.yaml: $key" "$W/bad.txt" || { echo "no message for $kv"; cat "$W/bad.txt"; exit 1; }
done
exit 0
