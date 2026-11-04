#!/bin/bash
# FX-32 (B-03): jobs/01_check_inputs.sbatch checks manifests/pacbio_deposited_fastq.tsv
# in addition to the three read manifests, and exits non-zero (code 5) when any row in
# archive_check.tsv has status != 'ok' (even if md5sum -c CHECKSUMS.md5 exited 0).
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

export INPUT="$W/input"
export RESULTS="$W/results"
export PY="python3"
mkdir -p "$INPUT/manifests" "$INPUT/pacbio/R1" "$INPUT/rnaseq/R2" "$INPUT/illumina2013/R3" "$INPUT/pacbio_deposited/SRR5086624" "$RESULTS/01_inputs"

printf 'pacbio_data' > "$INPUT/pacbio/R1/a.bax.h5"
printf 'rnaseq_data' > "$INPUT/rnaseq/R2/R2"
printf 'illumina_data' > "$INPUT/illumina2013/R3/R3"
printf 'deposited_data' > "$INPUT/pacbio_deposited/SRR5086624/Hw_PacBio.filtered_subreads.fastq.bz2"

md5_pb="$(md5sum "$INPUT/pacbio/R1/a.bax.h5" | awk '{print $1}')"
md5_rna="$(md5sum "$INPUT/rnaseq/R2/R2" | awk '{print $1}')"
md5_ill="$(md5sum "$INPUT/illumina2013/R3/R3" | awk '{print $1}')"
md5_dep="$(md5sum "$INPUT/pacbio_deposited/SRR5086624/Hw_PacBio.filtered_subreads.fastq.bz2" | awk '{print $1}')"

cat > "$INPUT/CHECKSUMS.md5" <<EOF
$md5_pb  ./pacbio/R1/a.bax.h5
$md5_rna  ./rnaseq/R2/R2
$md5_ill  ./illumina2013/R3/R3
$md5_dep  ./pacbio_deposited/SRR5086624/Hw_PacBio.filtered_subreads.fastq.bz2
EOF

printf 'run\tname\tsize\tmd5\turl\nR1\ta.bax.h5\t11\t%s\thttps://example.org/pb\n' "$md5_pb" > "$INPUT/manifests/pacbio_files.tsv"
printf 'run\tname\tsize\tmd5\turl\nR2\tR2\t11\t%s\thttps://example.org/rna\n' "$md5_rna" > "$INPUT/manifests/rna_sra_files.tsv"
printf 'run\tname\tsize\tmd5\turl\nR3\tR3\t13\t%s\thttps://example.org/ill\n' "$md5_ill" > "$INPUT/manifests/illumina2013_sra_files.tsv"
printf 'run\tname\tsize\tmd5\turl\nSRR5086624\tHw_PacBio.filtered_subreads.fastq.bz2\t14\t%s\thttps://example.org/dep\n' "$md5_dep" > "$INPUT/manifests/pacbio_deposited_fastq.tsv"

# 1. Positive case: all 4 manifests (including pacbio_deposited) match CHECKSUMS.md5 and disk
(
  cd "$INPUT"
  eval "$(sed -n '/^# (1) file by file/,/^PYEOF/p' "$HW/jobs/01_check_inputs.sbatch")"
) > "$W/ok.out" 2>&1 || {
  echo "FAIL: 01_check_inputs block failed when all 4 manifests match" >&2
  cat "$W/ok.out" >&2
  exit 1
}

python3 - "$RESULTS/01_inputs/archive_check.tsv" "$md5_dep" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
dep = [r for r in rows if r['group'] == 'pacbio_deposited']
if len(dep) != 1:
    sys.exit(f"FAIL: expected 1 pacbio_deposited row in archive_check.tsv, got {len(dep)} (rows={rows})")
if dep[0]['status'] != 'ok' or dep[0]['md5_found'] != sys.argv[2]:
    sys.exit(f"FAIL: pacbio_deposited row not ok: {dep[0]}")
PY

# 2. Negative case: CHECKSUMS.md5 and disk agree (rc1=0), but pacbio_deposited_fastq.tsv has a different archive md5 -> must exit non-zero
printf 'run\tname\tsize\tmd5\turl\nSRR5086624\tHw_PacBio.filtered_subreads.fastq.bz2\t14\t00000000000000000000000000000000\thttps://example.org/dep\n' > "$INPUT/manifests/pacbio_deposited_fastq.tsv"
set +e
(
  cd "$INPUT"
  eval "$(sed -n '/^# (1) file by file/,/^PYEOF/p' "$HW/jobs/01_check_inputs.sbatch")"
) > "$W/diff.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || {
  echo "FAIL: 01_check_inputs block exited 0 when archive_check.tsv had status=DIFFERENT" >&2
  cat "$W/diff.out" >&2
  exit 1
}
grep -q "ERROR: a file differs from the archive record" "$W/diff.out" || {
  echo "FAIL: expected error message on stderr when archive_check.tsv has DIFFERENT" >&2
  cat "$W/diff.out" >&2
  exit 1
}

echo "PASS"
