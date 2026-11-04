#!/bin/bash
# FX-18: 09_replicates.sh writes 'missing' (not the checksum of an empty file) for an absent FASTA.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/envs/04_probe/bin" "$W/work/asm/proc_r1_raw" "$W/work/asm/proc_r1" "$W/results" "$W/dbs"
ln -s "$(command -v python3)" "$W/envs/04_probe/bin/python"

# Provide valid FASTA files for r1, leave r2 and r3 absent
printf ">c1\nACGTACGT\n" > "$W/work/asm/proc_r1_raw/corrected.fasta"
printf ">c1\nACGTACGT\n" > "$W/work/asm/proc_r1_raw/final.fasta"
printf ">c1\nACGTACGT\n" > "$W/work/asm/proc_r1/final.fasta"

HW="$HW" HW_RESULTS="$W/results" HW_WORK="$W/work" HW_ENVS="$W/envs" HW_DBS="$W/dbs" bash "$HW/scripts/09_replicates.sh" > "$W/out.txt" 2>&1 || {
  echo "09_replicates.sh failed:"
  cat "$W/out.txt"
  exit 1
}

python3 - "$W/results/09_summary/replicate_check.tsv" <<'PY'
import csv, sys, hashlib
EMPTY_MD5 = "d41d8cd98f00b204e9800998ecf8427e"
rows = {r['run']: r for r in csv.DictReader(open(sys.argv[1]), delimiter='\t')}
md5_cols = [
    'corrected_reads_md5_sorted',
    'raw_assembly_md5',
    'polished_assembly_md5',
    'polished_assembly_md5_file_as_written',
    'polished_assembly_sequences_md5',
]
# r1 must have real 32-hex checksums
for c in md5_cols:
    v = rows['proc_r1'][c]
    literal = (b">c1\nACGTACGT\n" if c == 'polished_assembly_md5_file_as_written'
               else b"ACGTACGT" if c == 'polished_assembly_sequences_md5'
               else b">c1\tACGTACGT\n")
    expected = hashlib.md5(literal).hexdigest()
    assert v == expected, f"proc_r1 {c}: expected {expected}, got {v!r}"
# r2 and r3 have absent FASTAs: must be 'missing', never EMPTY_MD5 or ''
for run in ('proc_r2', 'proc_r3'):
    for c in md5_cols:
        v = rows[run][c]
        if v == EMPTY_MD5:
            sys.exit(f"FAIL: {run} {c} is {EMPTY_MD5} (MD5 of empty input) instead of 'missing'")
        if v != 'missing':
            sys.exit(f"FAIL: {run} {c} is {v!r} instead of 'missing'")
PY
