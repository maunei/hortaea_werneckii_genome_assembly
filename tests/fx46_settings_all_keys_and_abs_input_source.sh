#!/bin/bash
# FX-41: (b) stage_settings in setup_and_run_all.sh checks all keys (account, mail_address, modules,
# finished_job_name, mail_when) against quotes, backslashes, backticks and $, and requires input_source
# to be an absolute path with clear refusal messages.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/repo/config" "$W/rel_input" "$W/abs_input"
cp "$HW/setup_and_run_all.sh" "$W/repo/setup_and_run_all.sh"

write_settings() {
  local file="$1"
  shift
  cat > "$file" <<EOF
account: def-test_cpu
mail_address: user@domain.org
mail_when: FAIL
modules: StdEnv/2023
finished_job_name: hw_run_finished
work_dir: $W/work
envs_dir: $W/envs
dbs_dir: $W/dbs
input_source: "$W/abs_input"
EOF
  for ov in "$@"; do
    local k="${ov%%:*}"
    grep -v "^${k}:" "$file" > "$file.tmp"
    printf '%s\n' "$ov" >> "$file.tmp"
    mv "$file.tmp" "$file"
  done
}

# 1. Valid settings with absolute input_source must pass
write_settings "$W/good.yaml"
bash "$W/repo/setup_and_run_all.sh" settings "$W/good.yaml" > "$W/good.out" 2>&1 || {
  echo "FAIL: stage_settings rejected valid settings.yaml" >&2
  cat "$W/good.out" >&2
  exit 1
}

# 2. Bad characters (quote, backslash, backtick, $) in account, mail_address, modules, finished_job_name must be refused
for spec in \
  'account: "def-test\"extra"' \
  'account: def-test$var' \
  'mail_address: user`id`@domain.org' \
  'modules: StdEnv/2023\bad' \
  'finished_job_name: "hw_done"extra' \
  'finished_job_name: hw_$done'
do
  k="${spec%%:*}"
  write_settings "$W/bad_$k.yaml" "$spec"
  if bash "$W/repo/setup_and_run_all.sh" settings "$W/bad_$k.yaml" > "$W/bad_$k.out" 2>&1; then
    echo "FAIL: stage_settings accepted forbidden character in '$spec'" >&2
    exit 1
  fi
  grep -q "settings.yaml: $k holds a quote, a backslash, a backtick or a dollar sign" "$W/bad_$k.out" || {
    echo "FAIL: unexpected refusal message for '$spec': $(cat "$W/bad_$k.out")" >&2
    exit 1
  }
done

# 3. Relative input_source (even when directory exists relative to repo) must be refused as non-absolute
mkdir -p "$W/repo/rel_source_dir"
write_settings "$W/bad_rel.yaml" "input_source: rel_source_dir"
if bash "$W/repo/setup_and_run_all.sh" settings "$W/bad_rel.yaml" > "$W/bad_rel.out" 2>&1; then
  echo "FAIL: stage_settings accepted relative input_source 'rel_source_dir'" >&2
  exit 1
fi
grep -q "settings.yaml: input_source must be an absolute path" "$W/bad_rel.out" || {
  echo "FAIL: missing 'input_source must be an absolute path' message: $(cat "$W/bad_rel.out")" >&2
  exit 1
}

echo "PASS"
