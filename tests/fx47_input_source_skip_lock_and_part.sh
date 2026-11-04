#!/bin/bash
# FX-42: (c) stage_inputs in setup_and_run_all.sh skips .fetch.lock, *.part, and fetch_report.tsv
# when linking files from input_source into input/.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/repo/config" "$W/repo/input/manifests" "$W/src/pacbio/R1" "$W/src/pacbio_deposited/R2"
cp "$HW/setup_and_run_all.sh" "$W/repo/setup_and_run_all.sh"
cp "$HW/config/config.sh" "$W/repo/config/config.sh"

# Create real files + transient/lock files in INPUT_SOURCE
printf 'subreads\n' > "$W/src/pacbio/R1/movie.bax.h5"
printf 'deposited\n' > "$W/src/pacbio_deposited/R2/dep.fastq.bz2"
printf 'lock\n' > "$W/src/.fetch.lock"
printf 'lock\n' > "$W/src/pacbio/.fetch.lock"
printf 'partial\n' > "$W/src/pacbio/R1/movie.bax.h5.12345.part"
printf 'report\n' > "$W/src/pacbio/fetch_report.tsv"

MD5_1="$(md5sum "$W/src/pacbio/R1/movie.bax.h5" | awk '{print $1}')"
MD5_2="$(md5sum "$W/src/pacbio_deposited/R2/dep.fastq.bz2" | awk '{print $1}')"
printf '%s  ./pacbio/R1/movie.bax.h5\n' "$MD5_1" > "$W/repo/input/CHECKSUMS.md5"

for m in pacbio_files rna_sra_files illumina2013_sra_files; do
  printf 'run\tname\tsize\tmd5\turl\n' > "$W/repo/input/manifests/$m.tsv"
done
printf 'run\tname\tsize\tmd5\turl\nR2\tdep.fastq.bz2\t10\t%s\thttps://example.org/dep\n' "$MD5_2" > "$W/repo/input/manifests/pacbio_deposited_fastq.tsv"

cat > "$W/repo/settings.yaml" <<EOF
account: def-test_cpu
mail_when: NONE
modules:
work_dir: $W/work
envs_dir: $W/envs
dbs_dir: $W/dbs
input_source: $W/src
EOF

bash "$W/repo/setup_and_run_all.sh" settings "$W/repo/settings.yaml" > /dev/null
bash "$W/repo/setup_and_run_all.sh" inputs "$W/repo/settings.yaml" > "$W/inputs.out" 2>&1 || {
  echo "FAIL: stage_inputs failed on complete input_source" >&2
  cat "$W/inputs.out" >&2
  exit 1
}

[ -L "$W/repo/input/pacbio/R1/movie.bax.h5" ] || { echo "FAIL: real file movie.bax.h5 was not linked" >&2; exit 1; }
[ -L "$W/repo/input/pacbio_deposited/R2/dep.fastq.bz2" ] || { echo "FAIL: deposited file was not linked" >&2; exit 1; }
[ ! -e "$W/repo/input/.fetch.lock" ] && [ ! -L "$W/repo/input/.fetch.lock" ] || { echo "FAIL: root .fetch.lock was linked from input_source" >&2; exit 1; }
[ ! -e "$W/repo/input/pacbio/.fetch.lock" ] && [ ! -L "$W/repo/input/pacbio/.fetch.lock" ] || { echo "FAIL: pacbio/.fetch.lock was linked from input_source" >&2; exit 1; }
[ ! -e "$W/repo/input/pacbio/R1/movie.bax.h5.12345.part" ] && [ ! -L "$W/repo/input/pacbio/R1/movie.bax.h5.12345.part" ] || { echo "FAIL: *.part file was linked from input_source" >&2; exit 1; }
[ ! -e "$W/repo/input/pacbio/fetch_report.tsv" ] && [ ! -L "$W/repo/input/pacbio/fetch_report.tsv" ] || { echo "FAIL: fetch_report.tsv was linked from input_source" >&2; exit 1; }

echo "PASS"
