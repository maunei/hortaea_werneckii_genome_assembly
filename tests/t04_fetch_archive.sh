#!/bin/bash
# the download: never writes through a link (final name or temporary name), replaces a file of the wrong size, leaves no temporary file after a failure, rejects a wrong checksum
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/src" "$W/shared"
head -c 100000 /dev/urandom > "$W/src/data.bin"; md5=$(md5sum "$W/src/data.bin" | cut -d' ' -f1); size=$(stat -c %s "$W/src/data.bin")
mk() { printf 'run\tname\tsize\tmd5\turl\nR\tdata.bin\t%s\t%s\tfile://%s\n' "$size" "$1" "$W/src/data.bin" > "$W/m.tsv"; }
run() { python3 "$HW/scripts/fetch_archive.py" "$W/m.tsv" "$W/dest" 2 > "$W/out.txt" 2>&1; }
fresh() { rm -rf "$W/dest"; mkdir -p "$W/dest/R"; }
# 1. a link to a shared file at the final name is replaced, not written through
mk "$md5"; fresh; echo precious > "$W/shared/a"; ln -s "$W/shared/a" "$W/dest/R/data.bin"
run || { cat "$W/out.txt"; echo "case 1: the download failed"; exit 1; }
[ "$(cat "$W/shared/a")" = precious ] || { echo "case 1: the file behind the link was changed"; exit 1; }
[ ! -L "$W/dest/R/data.bin" ] && cmp -s "$W/src/data.bin" "$W/dest/R/data.bin" || { echo "case 1: the final file is not the downloaded file"; exit 1; }
# 2. a link at the name data.bin.part is not written through either
fresh; echo precious2 > "$W/shared/b"; ln -s "$W/shared/b" "$W/dest/R/data.bin.part"
run || { cat "$W/out.txt"; echo "case 2: the download failed"; exit 1; }
[ "$(cat "$W/shared/b")" = precious2 ] || { echo "case 2: the file behind the .part link was changed"; exit 1; }
cmp -s "$W/src/data.bin" "$W/dest/R/data.bin" || { echo "case 2: the final file is not the downloaded file"; exit 1; }
# 3. a regular file of the wrong size (with a marker) is replaced
fresh; echo short > "$W/dest/R/data.bin"; echo "$md5" > "$W/dest/R/data.bin.md5ok"
run || { cat "$W/out.txt"; echo "case 3: the download failed"; exit 1; }
cmp -s "$W/src/data.bin" "$W/dest/R/data.bin" || { echo "case 3: the file of the wrong size was not replaced"; exit 1; }
# 4. a wrong checksum: the download fails, no file under the final name, no temporary file left
mk 00000000000000000000000000000000; fresh
run && { echo "case 4: a wrong checksum was accepted"; exit 1; }
[ ! -e "$W/dest/R/data.bin" ] || { echo "case 4: a file with a wrong checksum is kept under the final name"; exit 1; }
ls "$W"/dest/R/data.bin*.part > /dev/null 2>&1 && { echo "case 4: a temporary .part file is left"; exit 1; }
exit 0
