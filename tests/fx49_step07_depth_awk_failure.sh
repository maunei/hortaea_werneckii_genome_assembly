#!/bin/bash
# FX-44: (e) scripts/07_depth.sh propagates failures of both awk steps (exit 5)
# and does not leave a partial depth.per_contig.tsv or reads_used.txt when either awk fails.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT

mkdir -p "$W/repo/scripts" "$W/repo/config" "$W/envs/04_I_qc/bin" "$W/work" "$W/dbs"
cp "$HW/scripts/07_depth.sh" "$W/repo/scripts/07_depth.sh"
cp "$HW/config/config.sh" "$W/repo/config/config.sh"

# Mock minimap2, samtools, mosdepth in QC_BIN
cat > "$W/envs/04_I_qc/bin/minimap2" <<'EOF'
#!/bin/bash
printf '@HD\tVN:1.6\tSO:unsorted\n@SQ\tSN:ctg1\tLN:1000\n'
EOF
cat > "$W/envs/04_I_qc/bin/samtools" <<'EOF'
#!/bin/bash
case "$1" in
  sort)
    while [ $# -gt 0 ]; do
      if [ "$1" = "-o" ]; then out="$2"; break; fi
      shift
    done
    cat > "$out"
    ;;
  index) touch "$2.bai" ;;
  flagstat) echo "10 + 0 in total" ;;
esac
EOF
cat > "$W/envs/04_I_qc/bin/mosdepth" <<'EOF'
#!/bin/bash
prefix="${@: -2:1}"
if [ "${SKIP_MOSDEPTH_SUMMARY:-0}" = "1" ]; then
  exit 0
fi
printf 'chrom\tlength\tbases\tmean\tmin\tmax\nctg1\t1000\t25000\t25.0\t10\t40\ntotal\t1000\t25000\t25.0\t10\t40\n' > "${prefix}.mosdepth.summary.txt"
EOF
chmod +x "$W/envs/04_I_qc/bin/minimap2" "$W/envs/04_I_qc/bin/samtools" "$W/envs/04_I_qc/bin/mosdepth"

FASTA="$W/asm.fasta"
READS="$W/reads.fastq"
printf '>ctg1\nACGTACGT\n' > "$FASTA"
printf '@r1\nACGTACGT\n+\nIIIIIIII\n' > "$READS"

# 1. Second awk fails when mosdepth summary file is missing -> must exit 5 and not leave depth.per_contig.tsv or reads_used.txt
rc=0
SKIP_MOSDEPTH_SUMMARY=1 HW="$W/repo" HW_WORK="$W/work" HW_ENVS="$W/envs" HW_DBS="$W/dbs" \
  bash "$W/repo/scripts/07_depth.sh" test_fail2 "$FASTA" "$READS" 2 > "$W/fail2.out" 2>&1 || rc=$?
[ "$rc" -eq 5 ] || { echo "FAIL: 07_depth.sh exited $rc (expected 5) when second awk failed" >&2; cat "$W/fail2.out" >&2; exit 1; }
[ ! -e "$W/work/07_comparator/test_fail2/depth.per_contig.tsv" ] || { echo "FAIL: depth.per_contig.tsv created when second awk failed" >&2; exit 1; }
[ ! -e "$W/work/07_comparator/test_fail2/reads_used.txt" ] || { echo "FAIL: reads_used.txt created when second awk failed" >&2; exit 1; }

# 2. First awk fails (mock awk failing on 1st call) -> must exit 5
mkdir -p "$W/mockbin"
REAL_AWK="$(command -v awk)"
cat > "$W/mockbin/awk" <<EOF
#!/bin/bash
if [ "\${FAIL_FIRST_AWK:-0}" = "1" ]; then exit 2; fi
exec "$REAL_AWK" "\$@"
EOF
chmod +x "$W/mockbin/awk"

rc=0
PATH="$W/mockbin:$PATH" FAIL_FIRST_AWK=1 HW="$W/repo" HW_WORK="$W/work" HW_ENVS="$W/envs" HW_DBS="$W/dbs" \
  bash "$W/repo/scripts/07_depth.sh" test_fail1 "$FASTA" "$READS" 2 > "$W/fail1.out" 2>&1 || rc=$?
[ "$rc" -eq 5 ] || { echo "FAIL: 07_depth.sh exited $rc (expected 5) when first awk failed" >&2; cat "$W/fail1.out" >&2; exit 1; }
[ ! -e "$W/work/07_comparator/test_fail1/depth.per_contig.tsv" ] || { echo "FAIL: depth.per_contig.tsv created when first awk failed" >&2; exit 1; }

# 3. Normal run succeeds and writes depth.per_contig.tsv and reads_used.txt
HW="$W/repo" HW_WORK="$W/work" HW_ENVS="$W/envs" HW_DBS="$W/dbs" \
  bash "$W/repo/scripts/07_depth.sh" test_ok "$FASTA" "$READS" 2 > "$W/ok.out" 2>&1 || {
  echo "FAIL: 07_depth.sh failed on valid inputs" >&2
  cat "$W/ok.out" >&2
  exit 1
}
grep -q $'^ctg1\t8\t25.0\t25.0$' "$W/work/07_comparator/test_ok/depth.per_contig.tsv" || {
  echo "FAIL: unexpected depth.per_contig.tsv content: $(cat "$W/work/07_comparator/test_ok/depth.per_contig.tsv")" >&2
  exit 1
}
[ -s "$W/work/07_comparator/test_ok/reads_used.txt" ] || { echo "FAIL: reads_used.txt missing on valid run" >&2; exit 1; }

echo "PASS"
