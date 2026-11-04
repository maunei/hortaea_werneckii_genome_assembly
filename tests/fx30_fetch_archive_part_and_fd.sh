#!/bin/bash
# FX-30 (B-05): scripts/fetch_archive.py removes the unfinished NAME.*.part files of earlier attempts
# closes the file descriptor even if os.ftruncate fails,
# and does not fail when fetch_report.tsv cannot be written.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT

SRC="$W/src_data.bin"
printf '0123456789abcdef' > "$SRC"
MD5="$(md5sum "$SRC" | awk '{print $1}')"
SZ="$(wc -c < "$SRC" | tr -d ' ')"

MANIFEST="$W/manifest.tsv"
printf 'run\tname\tsize\tmd5\turl\nR1\tdata.bin\t%s\t%s\tfile://%s\n' "$SZ" "$MD5" "$SRC" > "$MANIFEST"

# 1. Every unfinished NAME.*.part file of the folder is removed before the download (the folder lock is held, so no other downloader is running): old and recent ones
DEST="$W/dest"
mkdir -p "$DEST/R1"
STALE_PART="$DEST/R1/data.bin.stale001.part"
FRESH_PART="$DEST/R1/data.bin.fresh001.part"
printf 'old_partial' > "$STALE_PART"
printf 'active_partial' > "$FRESH_PART"
python3 - "$STALE_PART" "$FRESH_PART" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now - 1200, now - 1200))
os.utime(sys.argv[2], (now, now))
PY

python3 "$HW/scripts/fetch_archive.py" "$MANIFEST" "$DEST" 2 > "$W/fetch1.out" 2>&1 || {
  echo "FAIL: fetch_archive.py failed on valid local manifest" >&2
  cat "$W/fetch1.out" >&2
  exit 1
}
cmp -s "$SRC" "$DEST/R1/data.bin" || { echo "FAIL: downloaded data.bin does not match source" >&2; exit 1; }
[ ! -e "$STALE_PART" ] || { echo "FAIL: stale .part file (>15 min) was not removed: $STALE_PART" >&2; exit 1; }
[ ! -e "$FRESH_PART" ] || { echo "FAIL: recent .part file was not removed: $FRESH_PART" >&2; exit 1; }

# 2. File descriptor is closed even when os.ftruncate raises OSError (e.g. ENOSPC)
DEST2="$W/dest_fd"
mkdir -p "$DEST2/R1"
python3 - "$HW/scripts/fetch_archive.py" "$MANIFEST" "$DEST2" <<'PY'
import os, sys, errno

script, man, dest = sys.argv[1], sys.argv[2], sys.argv[3]
recorded_fds = []
real_ftruncate = os.ftruncate

def boom_ftruncate(fd, length):
    recorded_fds.append(fd)
    raise OSError(errno.ENOSPC, "simulated ENOSPC in ftruncate")

os.ftruncate = boom_ftruncate
sys.argv = [script, man, dest, "1"]
try:
    with open(script) as f:
        code = compile(f.read(), script, "exec")
    exec(code, {"__name__": "__main__", "__file__": script})
except SystemExit:
    pass
except OSError:
    pass

if not recorded_fds:
    sys.exit("FAIL: os.ftruncate was never called")

for fd in recorded_fds:
    try:
        os.fstat(fd)
        sys.exit(f"FAIL: file descriptor {fd} leaked (still open after ftruncate failure)")
    except OSError as e:
        if e.errno != errno.EBADF:
            raise
PY

# 3. Unwritable fetch_report.tsv warns on stderr and does not fail a verified download
DEST3="$W/dest_ro_report"
mkdir -p "$DEST3/R1"
cp "$SRC" "$DEST3/R1/data.bin"
printf '%s\n' "$MD5" > "$DEST3/R1/data.bin.md5ok"
mkdir -p "$DEST3/fetch_report.tsv"   # directory at report path causes OSError when replacing/writing report
python3 "$HW/scripts/fetch_archive.py" "$MANIFEST" "$DEST3" 1 > "$W/fetch3.out" 2>&1 || {
  echo "FAIL: fetch_archive.py failed when fetch_report.tsv could not be written" >&2
  cat "$W/fetch3.out" >&2
  exit 1
}
grep -q "WARNING: the report" "$W/fetch3.out" || {
  echo "FAIL: expected warning when fetch_report.tsv cannot be written" >&2
  cat "$W/fetch3.out" >&2
  exit 1
}

echo "PASS"
