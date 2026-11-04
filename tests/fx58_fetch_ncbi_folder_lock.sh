#!/bin/bash
# Regression test for Round D fix D-04 (fetch_ncbi folder lock in jobs/01_fetch_inputs.sbatch):
# 1. fetch_ncbi acquires an exclusive lock on $(dirname "$out")/.fetch.lock.
# 2. If $(dirname "$out")/.fetch.lock cannot be opened or locked (e.g., it is a
#    directory), fetch_ncbi exits with code 6 and does not remove existing
#    .part files in that folder.
set -euo pipefail
HW="$(cd "$(dirname "$0")/.." && pwd)"; cd "$HW"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Extract fetch_ncbi function from jobs/01_fetch_inputs.sbatch
sed -n '/^fetch_ncbi()/,/^}/p' "$HW/jobs/01_fetch_inputs.sbatch" > "$T/fetch_ncbi.sh"
[ -s "$T/fetch_ncbi.sh" ] || { echo "FAIL: could not extract fetch_ncbi from jobs/01_fetch_inputs.sbatch" >&2; exit 1; }

mkdir -p "$T/bin" "$T/assembly"
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift 2; else shift; fi
done
printf 'fake-ncbi-payload' > "$out"
EOF
chmod +x "$T/bin/curl"
MD5="$(printf 'fake-ncbi-payload' | md5sum | awk '{print $1}')"

# Case 1: Lock failure (make .fetch.lock a directory) -> must exit 6 and leave existing .part untouched
touch "$T/assembly/GCA_test.fna.gz.99999.part"
mkdir -p "$T/assembly/.fetch.lock"

rc=0
PATH="$T/bin:$PATH" bash -c "source '$T/fetch_ncbi.sh'; fetch_ncbi '$T/assembly/GCA_test.fna.gz' 'https://example.org/file' '$MD5'" > "$T/case1.log" 2>&1 || rc=$?
if [ "$rc" -ne 6 ]; then
  echo "FAIL: expected fetch_ncbi to exit 6 when .fetch.lock cannot be opened, got $rc" >&2
  cat "$T/case1.log" >&2
  exit 1
fi
if [ ! -e "$T/assembly/GCA_test.fna.gz.99999.part" ]; then
  echo "FAIL: fetch_ncbi deleted .part file without holding the folder lock" >&2
  exit 1
fi

# Case 2: Normal run creates .fetch.lock, cleans stale .part, and installs verified file
rmdir "$T/assembly/.fetch.lock"
PATH="$T/bin:$PATH" bash -c "source '$T/fetch_ncbi.sh'; fetch_ncbi '$T/assembly/GCA_test.fna.gz' 'https://example.org/file' '$MD5'" > "$T/case2.log" 2>&1
[ -f "$T/assembly/.fetch.lock" ] || { echo "FAIL: fetch_ncbi did not create .fetch.lock" >&2; exit 1; }
[ ! -e "$T/assembly/GCA_test.fna.gz.99999.part" ] || { echo "FAIL: fetch_ncbi did not clean stale .part file under lock" >&2; exit 1; }
[ -s "$T/assembly/GCA_test.fna.gz" ] || { echo "FAIL: fetch_ncbi did not install target file" >&2; exit 1; }

echo "fx58_fetch_ncbi_folder_lock: OK"
