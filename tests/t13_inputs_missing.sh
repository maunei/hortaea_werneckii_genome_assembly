#!/bin/bash
# t13: the stage inputs counts a missing input file as missing: a file of CHECKSUMS.md5 and also the file deposited by the authors
# (manifests/pacbio_deposited_fastq.tsv), which CHECKSUMS.md5 does not list. Without it the stage would say "nothing to download".
set -uo pipefail
HW="${HW:?set HW to the repository root}"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export INPUT="$W/input"; mkdir -p "$INPUT/manifests" "$INPUT/pacbio/R1"
source <(sed -n '/^inputs_missing()/p' "$HW/setup_and_run_all.sh")
printf 'abc  pacbio/R1/a.h5\n' > "$INPUT/CHECKSUMS.md5"; : > "$INPUT/pacbio/R1/a.h5"
printf 'run\tname\tsize\tmd5\turl\nSRR5086624\tdep.fastq.bz2\t1\tx\thttp://x\n' > "$INPUT/manifests/pacbio_deposited_fastq.tsv"
fail=0; ck() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', expected '$3')"; fail=1; fi; }
ck "the deposited file is missing" "$(inputs_missing)" "pacbio_deposited/SRR5086624/dep.fastq.bz2"
mkdir -p "$INPUT/pacbio_deposited/SRR5086624"; : > "$INPUT/pacbio_deposited/SRR5086624/dep.fastq.bz2"
ck "everything present" "$(inputs_missing)" ""
rm "$INPUT/pacbio/R1/a.h5"
ck "a file of CHECKSUMS.md5 is missing" "$(inputs_missing)" "pacbio/R1/a.h5"
exit $fail
