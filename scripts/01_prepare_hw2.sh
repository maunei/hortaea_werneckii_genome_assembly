#!/bin/bash
# Step 01 (last part): makes the published assembly Hw 2.0 available as $WORK/asm/hw2/final.fasta, the file that every later step reads for it.
# The assembly is the file assemblies/Hw2/Hw2.fasta.gz of the GitHub repository of the study, decompressed without any change. Run from the workflow folder (login node: a few seconds).
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
SRC="$INPUT/hw2/github_Hortaea_werneckii/assemblies/Hw2/Hw2.fasta.gz"; [ -s "$SRC" ] || { echo "not found: $SRC (run jobs/01_fetch_inputs.sbatch)" >&2; exit 2; }
mkdir -p "$WORK/asm/hw2" || exit 3
TMP_FASTA=$(mktemp "$WORK/asm/hw2/final.fasta.XXXXXX.tmp") || exit 4
trap 'rm -f "$TMP_FASTA"' EXIT
chmod "$(printf '%o' $(( 0666 & ~$(umask) )))" "$TMP_FASTA" || exit 4
if ! zcat "$SRC" > "$TMP_FASTA"; then rm -f "$TMP_FASTA"; echo "ERROR: $SRC cannot be read (damaged file?): run jobs/01_fetch_inputs.sbatch again" >&2; exit 4; fi
[ -s "$TMP_FASTA" ] || { echo "ERROR: $SRC is empty" >&2; exit 4; }
mv "$TMP_FASTA" "$WORK/asm/hw2/final.fasta" || exit 4
echo "Hw 2.0: $(grep -c '>' "$WORK/asm/hw2/final.fasta") contigs written to $WORK/asm/hw2/final.fasta"
