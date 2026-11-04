#!/bin/bash
# FX-16: The stage inputs also downloads manifests/pacbio_deposited_fastq.tsv (SRR5086624)
# into input/pacbio_deposited/ and verifies it; 02_compare_deposited.sbatch keeps its guarded fallback.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export INPUT="$W/input" PY=python3
mkdir -p "$W/src" "$INPUT/manifests" "$INPUT/hw2"

# Prepare small dummy files and manifests pointing to file:// URLs
for name in pb rna ill dep; do
  printf "dummy-$name\n" > "$W/src/$name.bin"
done
mk_man() {
  local src="$1" run="$2" fn="$3" out="$4"
  local md5 sz; md5=$(md5sum "$src" | awk '{print $1}'); sz=$(stat -c%s "$src")
  printf 'run\tname\tsize\tmd5\turl\n%s\t%s\t%s\t%s\tfile://%s\n' "$run" "$fn" "$sz" "$md5" "$src" > "$out"
}
mk_man "$W/src/pb.bin"  "SRR5086620" "m1.bax.h5" "$INPUT/manifests/pacbio_files.tsv"
mk_man "$W/src/rna.bin" "SRR5086621" "SRR5086621" "$INPUT/manifests/rna_sra_files.tsv"
mk_man "$W/src/ill.bin" "SRR866616"  "SRR866616"  "$INPUT/manifests/illumina2013_sra_files.tsv"
mk_man "$W/src/dep.bin" "SRR5086624" "Hw_PacBio.filtered_subreads.fastq.bz2" "$INPUT/manifests/pacbio_deposited_fastq.tsv"

# Run the fetch_archive.py section of jobs/01_fetch_inputs.sbatch
(
  eval "$(sed -n '/^mkdir -p "\$INPUT\/pacbio"/,/^# Hw 2.0:/p' "$HW/jobs/01_fetch_inputs.sbatch")"
) > "$W/out.txt" 2>&1 || { cat "$W/out.txt"; exit 1; }

# 1. Verify positive baseline: pacbio, rnaseq, illumina2013 were downloaded
[ -s "$INPUT/pacbio/SRR5086620/m1.bax.h5" ] || { echo "baseline pacbio download did not run"; exit 1; }

# 2. Verify pacbio_deposited_fastq.tsv was downloaded into input/pacbio_deposited/ and verified (.md5ok)
DEP="$INPUT/pacbio_deposited/SRR5086624/Hw_PacBio.filtered_subreads.fastq.bz2"
[ -s "$DEP" ] && [ -s "$DEP.md5ok" ] || {
  echo "FAIL: jobs/01_fetch_inputs.sbatch did not download and verify manifests/pacbio_deposited_fastq.tsv into input/pacbio_deposited/"
  exit 1
}

# 3. Verify 02_compare_deposited.sbatch still keeps its guarded fallback
grep -q 'pacbio_deposited_fastq.tsv' "$HW/jobs/02_compare_deposited.sbatch" || {
  echo "FAIL: 02_compare_deposited.sbatch no longer has the fallback for pacbio_deposited_fastq.tsv"
  exit 1
}
exit 0
