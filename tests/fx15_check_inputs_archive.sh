#!/bin/bash
# FX-15: 01_check_inputs.sbatch: archive_check.tsv marks a missing or damaged file as not ok
# in every case that md5sum -c reports (FAILED, FAILED open or read); md5_found is not the expected value for a file that failed.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export INPUT="$W/input" RESULTS="$W/results" PY=python3
mkdir -p "$INPUT/manifests" "$INPUT/pacbio/R1" "$INPUT/rnaseq/R2" "$INPUT/illumina2013/R3" "$RESULTS/01_inputs"

# File 1: intact
printf 'intact-pacbio-content\n' > "$INPUT/pacbio/R1/ok.bax.h5"
md5_ok=$(md5sum "$INPUT/pacbio/R1/ok.bax.h5" | awk '{print $1}')
sz_ok=$(stat -c%s "$INPUT/pacbio/R1/ok.bax.h5")

# File 2: damaged on disk (expected md5 is md5_ok, actual content is different)
printf 'corrupted-rna-content\n' > "$INPUT/rnaseq/R2/R2"
md5_exp_rna="$md5_ok"
sz_rna=$(stat -c%s "$INPUT/rnaseq/R2/R2")

# File 3: missing on disk (illumina2013/R3/R3 does not exist)
md5_exp_ill="$md5_ok"

cat > "$INPUT/CHECKSUMS.md5" <<EOF
$md5_ok  ./pacbio/R1/ok.bax.h5
$md5_exp_rna  ./rnaseq/R2/R2
$md5_exp_ill  ./illumina2013/R3/R3
EOF

printf 'run\tname\tsize\tmd5\turl\nR1\tok.bax.h5\t%s\t%s\thttps://example.org/ok\n' "$sz_ok" "$md5_ok" > "$INPUT/manifests/pacbio_files.tsv"
printf 'run\tname\tsize\tmd5\turl\nR2\tR2\t%s\t%s\thttps://example.org/r2\n' "$sz_rna" "$md5_exp_rna" > "$INPUT/manifests/rna_sra_files.tsv"
printf 'run\tname\tsize\tmd5\turl\nR3\tR3\t100\t%s\thttps://example.org/r3\n' "$md5_exp_ill" > "$INPUT/manifests/illumina2013_sra_files.tsv"
printf 'run\tname\tsize\tmd5\turl\n' > "$INPUT/manifests/pacbio_deposited_fastq.tsv"

# Run parts (1) and (2) extracted from jobs/01_check_inputs.sbatch
(
  cd "$INPUT"
  eval "$(sed -n '/^# (1) file by file/,/^PYEOF/p' "$HW/jobs/01_check_inputs.sbatch")"
) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q 'a file differs from the archive record' "$W/out.txt" || { echo "the check block must stop with an error when a file differs from the archive record (rc=$rc)"; cat "$W/out.txt"; exit 1; }   # the table is written before the stop

python3 - "$RESULTS/01_inputs/archive_check.tsv" "$md5_ok" <<'PY'
import csv, sys
rows = {r['group']: r for r in csv.DictReader(open(sys.argv[1]), delimiter='\t')}
exp = sys.argv[2]
assert rows['pacbio']['status'] == 'ok' and rows['pacbio']['md5_found'] == exp, f"intact file should be ok: {rows['pacbio']}"
for grp, label in (('rnaseq', 'damaged (FAILED)'), ('illumina2013', 'missing (FAILED open or read)')):
    r = rows[grp]
    if r['status'] == 'ok':
        sys.exit(f"FAIL: {label} file {grp} was marked status='ok' in archive_check.tsv: {r}")
    if r['md5_found'] == exp:
        sys.exit(f"FAIL: {label} file {grp} has md5_found == expected md5 ({exp}) in archive_check.tsv: {r}")
PY
