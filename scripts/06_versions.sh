#!/bin/bash
# Step 06: writes envs/versions_06.tsv with the versions that the programs report (program, version, environment variable, purpose).
HW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$HW/config/config.sh"
OUT="$HW/envs/versions_06.tsv"
printf 'program\tversion\tenvironment\tpurpose\n' > "$OUT"
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$OUT"; }
row "BUSCO" "$(PATH="$BUSCO_BIN:$PATH" busco --version 2>&1 | sed 's/^BUSCO //')" '$BUSCO_BIN' "gene-space completeness, lineage fungi_odb10, genome mode"
row "miniprot" "$("$BUSCO_BIN/miniprot" --version 2>&1 | head -1)" '$BUSCO_BIN' "alignment of Swiss-Prot fungal proteins to the assembly (also the gene finder used inside BUSCO)"
row "STAR" "$("$RNA_BIN/STAR" --version 2>&1 | head -1)" '$RNA_BIN' "alignment of the RNA-seq read pairs"
row "minimap2" "$("$QC_BIN/minimap2" --version 2>&1 | head -1)" '$QC_BIN' "read-back of the PacBio reads (preset map-pb) and alignment of the contigs against each other (preset asm20)"
row "samtools" "$("$QC_BIN/samtools" --version 2>&1 | head -1 | sed 's/^samtools //')" '$QC_BIN' "sorting, indexing and reading the read-back alignments"
row "mosdepth" "$("$QC_BIN/mosdepth" --version 2>&1 | head -1 | sed 's/^mosdepth //')" '$QC_BIN' "read depth in windows of 1 kb"
row "Python" "$("$PY" -c 'import sys; print(sys.version.split()[0])')" '$PY' "summary scripts of step 06"
row "NumPy" "$("$PY" -c 'import numpy; print(numpy.__version__)')" '$PY' "summary scripts of step 06"
row "GNU time" "$(/usr/bin/time --version 2>&1 | head -1 | awk '{print $NF}')" 'system' "wall time and peak memory of each program in timings.tsv"
echo "written $OUT"
