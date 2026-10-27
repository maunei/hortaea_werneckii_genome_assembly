#!/bin/bash
# Step 01 (last part): makes the published assembly Hw 2.0 available as $WORK/asm/hw2/final.fasta, the file that every later step reads for it.
# The assembly is the file assemblies/Hw2/Hw2.fasta.gz of the GitHub repository of the study, decompressed without any change. Run from the workflow folder (login node: a few seconds).
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
SRC="$INPUT/hw2/github_Hortaea_werneckii/assemblies/Hw2/Hw2.fasta.gz"; [ -s "$SRC" ] || { echo "not found: $SRC (run jobs/01_fetch_inputs.sbatch)" >&2; exit 2; }
mkdir -p "$WORK/asm/hw2"; zcat "$SRC" > "$WORK/asm/hw2/final.fasta.tmp" && mv "$WORK/asm/hw2/final.fasta.tmp" "$WORK/asm/hw2/final.fasta"
echo "Hw 2.0: $(grep -c '>' "$WORK/asm/hw2/final.fasta") contigs written to $WORK/asm/hw2/final.fasta"
