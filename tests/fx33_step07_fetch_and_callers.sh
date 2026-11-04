#!/bin/bash
# FX-33 (B-09): Step 07 reference fetch scripts (07_fetch_mito_refs.sh, 07_fetch_rdna_refs.sh,
# fetch_screen_test_genomes.sh) write via temporary .part files and clean up on failure so a
# failed second download leaves no final file; callers 07_mito.sbatch and 07_the22.sbatch exit 2
# when a reference fetch script fails.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/repo/config" "$W/repo/scripts" "$W/repo/jobs" "$W/repo/envs" "$W/bin" "$W/dbs" "$W/work" "$W/results" "$W/logs"
cp "$HW/scripts/07_fetch_mito_refs.sh" "$HW/scripts/07_fetch_rdna_refs.sh" "$HW/scripts/fetch_screen_test_genomes.sh" "$W/repo/scripts/"
cp "$HW/jobs/07_mito.sbatch" "$HW/jobs/07_the22.sbatch" "$W/repo/jobs/"
export HW="$W/repo"

cat > "$W/repo/config/modules.sh" <<'EOF'
:
EOF
cat > "$W/repo/config/config.sh" <<EOF
export HW="$W/repo"
export DBS="$W/dbs"
export WORK="$W/work"
export RESULTS="$W/results"
export LOGS_BASE="$W/logs"
export PY="python3"
export SWISSPROT_FUNGI="$W/dbs/swissprot.faa"
EOF
cat > "$W/repo/config/lib.sh" <<'EOF'
hw_start() { export LOGDIR="$LOGS_BASE/job_$1"; mkdir -p "$LOGDIR"; }
hw_end() { :; }
EOF

cat > "$W/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$W/bin/sleep"

# Spy scripts for downstream python steps
cat > "$W/repo/scripts/07_mito_refs.py" <<'EOF'
import os, sys
if os.environ.get("MITO_PY_FAIL") == "1":
    sys.exit(1)
open("mito_genomes.fasta", "w").write(">m1\nACGT\n")
open("mito_proteins.faa", "w").write(">p1\nM\n")
open("mito_refs.tsv", "w").write("accession\torganism\tlength\tgenes\nNC_010222.1\tMycosphaerella\t4\t1\n")
EOF
cat > "$W/repo/scripts/07_mito.py" <<'EOF'
import os
open(os.environ["DOWNSTREAM_RAN"], "w").write("07_mito.py\n")
EOF
cat > "$W/repo/scripts/07_the22.py" <<'EOF'
import os
open(os.environ["DOWNSTREAM_RAN"], "w").write("07_the22.py\n")
EOF

# Mock curl controlled by CURL_MODE and a call counter file
cat > "$W/bin/curl" <<'EOF'
#!/bin/bash
cnt_file="${CURL_COUNT_FILE:?}"
n=0
[ -f "$cnt_file" ] && n=$(cat "$cnt_file")
n=$((n + 1))
echo "$n" > "$cnt_file"

out=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "-o" ]; then
    j=$((i + 1))
    out="${!j}"
  fi
done

emit() {
  if [ -n "$out" ]; then printf '%s' "$1" > "$out"; else printf '%s' "$1"; fi
}

case "${CURL_MODE:-ok}" in
  fail2)
    if [ "$n" -eq 1 ]; then
      emit $'>rec1\nACGT\n'
      exit 0
    else
      emit $'>partial_rec2\nAC'
      exit 22
    fi
    ;;
  two_records)
    if [ "$n" -le 2 ]; then emit $'>rec\nACGT\n'; else emit ""; fi
    exit 0
    ;;
  ok)
    emit $'>rec\nACGT\n'
    exit 0
    ;;
esac
EOF
chmod +x "$W/bin/curl"

export PATH="$W/bin:$PATH"
export CURL_COUNT_FILE="$W/curl.count"

# 1. 07_fetch_rdna_refs.sh: failing 2nd curl must exit non-zero and leave no rdna_hw.fasta
rm -rf "$W/dbs/rdna_refs"; : > "$CURL_COUNT_FILE"
if CURL_MODE=fail2 bash "$W/repo/scripts/07_fetch_rdna_refs.sh" > "$W/rdna_fail2.out" 2>&1; then
  echo "FAIL: 07_fetch_rdna_refs.sh succeeded when 2nd curl failed" >&2
  exit 1
fi
[ ! -e "$W/dbs/rdna_refs/rdna_hw.fasta" ] || {
  echo "FAIL: failed 2nd download in 07_fetch_rdna_refs.sh left behind final rdna_hw.fasta" >&2
  exit 1
}

# 2. 07_fetch_rdna_refs.sh: fewer than 3 FASTA records must fail and leave no rdna_hw.fasta
rm -rf "$W/dbs/rdna_refs"; : > "$CURL_COUNT_FILE"
if CURL_MODE=two_records bash "$W/repo/scripts/07_fetch_rdna_refs.sh" > "$W/rdna_two.out" 2>&1; then
  echo "FAIL: 07_fetch_rdna_refs.sh succeeded with only 2 FASTA records" >&2
  exit 1
fi
[ ! -e "$W/dbs/rdna_refs/rdna_hw.fasta" ] || {
  echo "FAIL: 2-record download in 07_fetch_rdna_refs.sh left behind final rdna_hw.fasta" >&2
  exit 1
}

# 3. 07_fetch_rdna_refs.sh: all downloads ok -> creates rdna_hw.fasta (3 records) and vector_marker_bla.faa
rm -rf "$W/dbs/rdna_refs"; : > "$CURL_COUNT_FILE"
CURL_MODE=ok bash "$W/repo/scripts/07_fetch_rdna_refs.sh" > "$W/rdna_ok.out" 2>&1 || {
  echo "FAIL: 07_fetch_rdna_refs.sh failed on valid mock curl" >&2
  cat "$W/rdna_ok.out" >&2
  exit 1
}
[ -s "$W/dbs/rdna_refs/rdna_hw.fasta" ] && [ -s "$W/dbs/rdna_refs/vector_marker_bla.faa" ] || {
  echo "FAIL: 07_fetch_rdna_refs.sh did not produce expected reference files" >&2
  exit 1
}

# 4. 07_fetch_mito_refs.sh: failing 2nd curl or failing 07_mito_refs.py must fail and leave nogb_NC_044132.1.gb
rm -rf "$W/dbs/mito_refs"; : > "$CURL_COUNT_FILE"
if CURL_MODE=fail2 bash "$W/repo/scripts/07_fetch_mito_refs.sh" > "$W/mito_fail2.out" 2>&1; then
  echo "FAIL: 07_fetch_mito_refs.sh succeeded when 2nd curl failed" >&2
  exit 1
fi
[ ! -e "$W/dbs/mito_refs/gb_NC_044132.1.gb" ] || {
  echo "FAIL: failed 2nd download in 07_fetch_mito_refs.sh left behind gb_NC_044132.1.gb" >&2
  exit 1
}

rm -rf "$W/dbs/mito_refs"; : > "$CURL_COUNT_FILE"
if CURL_MODE=ok MITO_PY_FAIL=1 bash "$W/repo/scripts/07_fetch_mito_refs.sh" > "$W/mito_pyfail.out" 2>&1; then
  echo "FAIL: 07_fetch_mito_refs.sh succeeded when 07_mito_refs.py failed" >&2
  exit 1
fi

# 5. fetch_screen_test_genomes.sh: failing 2nd curl must fail and leave no NC_009434.1.fa
rm -rf "$W/work/screen_test"; : > "$CURL_COUNT_FILE"
if CURL_MODE=fail2 bash "$W/repo/scripts/fetch_screen_test_genomes.sh" > "$W/stest_fail2.out" 2>&1; then
  echo "FAIL: fetch_screen_test_genomes.sh succeeded when 2nd curl failed" >&2
  exit 1
fi
[ ! -e "$W/work/screen_test/NC_009434.1.fa" ] || {
  echo "FAIL: failed 2nd download in fetch_screen_test_genomes.sh left behind NC_009434.1.fa" >&2
  exit 1
}

# 6. Callers jobs/07_mito.sbatch and jobs/07_the22.sbatch must exit 2 when reference fetch fails
rm -rf "$W/dbs/mito_refs" "$W/dbs/rdna_refs"
mkdir -p "$W/work/asm/hw2" "$W/results/07_comparator/genbank_files"
printf '>c1\nACGT\n' > "$W/work/asm/hw2/final.fasta"
printf 'id\nseq1\n' > "$W/results/07_comparator/genbank_files/the22_ids.tsv"

: > "$CURL_COUNT_FILE"
set +e
SLURM_SUBMIT_DIR="$W/repo" ASM=hw2 DOWNSTREAM_RAN="$W/ran_mito" CURL_MODE=fail2 bash "$W/repo/jobs/07_mito.sbatch" > "$W/job_mito.out" 2>&1
rc_mito=$?
set -e
[ "$rc_mito" -eq 2 ] || { echo "FAIL: 07_mito.sbatch exited $rc_mito (expected 2) when fetch failed" >&2; cat "$W/job_mito.out" >&2; exit 1; }
[ ! -e "$W/ran_mito" ] || { echo "FAIL: 07_mito.sbatch ran 07_mito.py after fetch failed" >&2; exit 1; }

: > "$CURL_COUNT_FILE"
set +e
SLURM_SUBMIT_DIR="$W/repo" DOWNSTREAM_RAN="$W/ran_the22" CURL_MODE=fail2 bash "$W/repo/jobs/07_the22.sbatch" > "$W/job_the22.out" 2>&1
rc_the22=$?
set -e
[ "$rc_the22" -eq 2 ] || { echo "FAIL: 07_the22.sbatch exited $rc_the22 (expected 2) when fetch failed" >&2; cat "$W/job_the22.out" >&2; exit 1; }
[ ! -e "$W/ran_the22" ] || { echo "FAIL: 07_the22.sbatch ran 07_the22.py after fetch failed" >&2; exit 1; }

echo "PASS"
