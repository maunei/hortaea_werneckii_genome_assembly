#!/bin/bash
# the download replaces a link to a shared source file instead of writing through it, and uses .part for the download
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/src" "$W/dest/R1" "$W/shared"
head -c 100000 /dev/urandom > "$W/src/data.bin"; md5=$(md5sum "$W/src/data.bin" | cut -d' ' -f1); size=$(stat -c %s "$W/src/data.bin")
printf 'run\tname\tsize\tmd5\turl\nR1\tdata.bin\t%s\t%s\tfile://%s\n' "$size" "$md5" "$W/src/data.bin" > "$W/m.tsv"
echo "precious" > "$W/shared/data.bin"; ln -s "$W/shared/data.bin" "$W/dest/R1/data.bin"
python3 "$HW/scripts/fetch_archive.py" "$W/m.tsv" "$W/dest" 2 > "$W/out.txt" 2>&1 || { cat "$W/out.txt"; exit 1; }
[ "$(cat "$W/shared/data.bin")" = precious ] || { echo "the file behind the link was changed"; exit 1; }
[ ! -L "$W/dest/R1/data.bin" ] || { echo "the link was kept"; exit 1; }
cmp -s "$W/src/data.bin" "$W/dest/R1/data.bin" || { echo "the downloaded file differs"; exit 1; }
[ ! -e "$W/dest/R1/data.bin.part" ] || { echo "a .part file is left"; exit 1; }
# a wrong checksum leaves no file under the final name
rm -f "$W/dest/R1/data.bin" "$W/dest/R1/data.bin.md5ok"; sed -i "s/$md5/00000000000000000000000000000000/" "$W/m.tsv"
python3 "$HW/scripts/fetch_archive.py" "$W/m.tsv" "$W/dest" 2 > "$W/out2.txt" 2>&1 && { echo "a wrong checksum was accepted"; exit 1; }
[ ! -e "$W/dest/R1/data.bin" ] || { echo "a file with a wrong checksum is kept under the final name"; exit 1; }
exit 0
