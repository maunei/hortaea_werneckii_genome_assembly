#!/bin/bash
# Regression test for Round D fix D-01 (fetch_archive.py lock failure):
# When DEST/.fetch.lock cannot be opened or locked (e.g. DEST/.fetch.lock is a
# directory or cannot be created), scripts/fetch_archive.py must exit with
# code 2 and must NOT remove any existing *.part files or modify any data in
# DEST.
set -euo pipefail
HW="$(cd "$(dirname "$0")/.." && pwd)"; cd "$HW"
PY="${PY:-python3}"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT

DEST="$T/dest"
mkdir -p "$DEST"

# Create an in-progress .part file and an existing report in DEST
echo "partial-data" > "$DEST/sample.fastq.gz.12345.part"
printf 'run_accession\trole\tfile\turl\tsize_bytes\tmd5_expected\tmd5_actual\tstatus\n' > "$DEST/download_report.tsv"
cp "$DEST/download_report.tsv" "$T/report_before.tsv"

# Make DEST/.fetch.lock a directory so opening it for writing raises OSError (IsADirectoryError)
mkdir -p "$DEST/.fetch.lock"

cat > "$T/manifest.tsv" <<'EOF'
run	name	size	md5	url_1	url_2
SRR000001	sample.fastq.gz	10	d41d8cd98f00b204e9800998ecf8427e	https://example.org/sample.fastq.gz	https://example.org/sample2.fastq.gz
EOF

rc=0
"$PY" "$HW/scripts/fetch_archive.py" "$T/manifest.tsv" "$DEST" 1 > "$T/out.log" 2>&1 || rc=$?

if [ "$rc" -ne 2 ]; then
  echo "FAIL: expected fetch_archive.py to exit 2 when .fetch.lock cannot be opened, got $rc" >&2
  cat "$T/out.log" >&2
  exit 1
fi

if [ ! -f "$DEST/sample.fastq.gz.12345.part" ]; then
  echo "FAIL: fetch_archive.py removed sample.fastq.gz.12345.part without holding the lock" >&2
  exit 1
fi

if ! cmp -s "$DEST/download_report.tsv" "$T/report_before.tsv"; then
  echo "FAIL: fetch_archive.py modified download_report.tsv without holding the lock" >&2
  exit 1
fi

echo "fx56_fetch_archive_lock_fail: OK"
