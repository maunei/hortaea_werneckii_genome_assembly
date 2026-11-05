#!/bin/bash
# t15: scripts/fetch_archive.py takes a lock on the destination folder: a second downloader of the same folder waits until the first has ended
# (it cannot delete the file that the first has installed, nor lose rows of its report); a downloader of another folder does not wait.
set -uo pipefail
HW="${HW:?set HW to the repository root}"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
printf 'payload\n' > "$W/src"; MD5=$(md5sum "$W/src" | cut -d' ' -f1); SZ=$(stat -c%s "$W/src")
printf 'run\tname\tsize\tmd5\turl\nR1\tf.bin\t%s\t%s\tfile://%s\n' "$SZ" "$MD5" "$W/src" > "$W/m.tsv"
mkdir -p "$W/d1" "$W/d2"
python3 - "$W/d1" "$W/release" <<'PY' &
import fcntl, sys, time, os
f = open(os.path.join(sys.argv[1], '.fetch.lock'), 'a'); fcntl.flock(f, fcntl.LOCK_EX)   # a downloader that is running in d1
open(os.path.join(sys.argv[1], 'held'), 'w').close(); t = time.time()
while not os.path.exists(sys.argv[2]) and time.time() - t < 120: time.sleep(0.1)      # it ends when the test creates the file "release"
PY
H=$!
for i in $(seq 1 200); do [ -e "$W/d1/held" ] && break; sleep 0.1; done
[ -e "$W/d1/held" ] || { echo "FAIL: the test could not take the lock"; exit 1; }
fail=0
# the test does not measure seconds (the start of Python can take several seconds on a busy or slow disk): it looks at what has happened while the lock is held
python3 "$HW/scripts/fetch_archive.py" "$W/m.tsv" "$W/d2" 2 > /dev/null 2>&1
kill -0 $H 2>/dev/null || { echo "FAIL: the test is wrong, the first downloader ended before the other one"; exit 1; }
cmp -s "$W/src" "$W/d2/R1/f.bin" || { echo "FAIL: a downloader of another folder did not finish while the first one held its lock"; fail=1; }
python3 "$HW/scripts/fetch_archive.py" "$W/m.tsv" "$W/d1" 2 > /dev/null 2>&1 &
D=$!
sleep 8   # more than the start of the downloader
kill -0 $D 2>/dev/null || { echo "FAIL: a downloader of the same folder did not wait for the lock"; fail=1; }
[ ! -e "$W/d1/R1/f.bin" ] || { echo "FAIL: a downloader of the same folder installed a file while the lock was held"; fail=1; }
touch "$W/release"; wait $D; wait $H
cmp -s "$W/src" "$W/d1/R1/f.bin" || { echo "FAIL: the downloader of the same folder did not install the file after the lock was released"; fail=1; }
[ $fail = 0 ] && echo ok
exit $fail
