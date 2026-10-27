#!/bin/bash
# Writes envs/versions_07.tsv: programs used by step 07 with the version read from each program.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
OUT="$HW/envs/versions_07.tsv"
printf 'program\tversion\tenvironment\tpurpose\n' > "$OUT"
add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$OUT"; }
add minimap2 "$("$QC_BIN/minimap2" --version)" '$QC_BIN' "alignment of contigs to contigs, of the 22 sequences, of mitochondrial genomes and of PacBio reads (preset map-pb)"
add samtools "$("$QC_BIN/samtools" --version | head -1 | cut -d' ' -f2)" '$QC_BIN' "sorting and indexing of read alignments"
add mosdepth "$("$QC_BIN/mosdepth" --version | cut -d' ' -f2)" '$QC_BIN' "read depth in windows of 1 kb and per contig"
add miniprot "$("$BLAST_BIN/miniprot" --version)" '$BLAST_BIN' "alignment of Swiss-Prot fungal proteins to the 22 sequences"
add tblastn "$("$BLAST_BIN/tblastn" -version | head -1 | cut -d' ' -f2)" '$BLAST_BIN' "alignment of mitochondrial proteins (genetic code 4) to contigs"
add makeblastdb "$("$BLAST_BIN/makeblastdb" -version | head -1 | cut -d' ' -f2)" '$BLAST_BIN' "nucleotide databases for tblastn"
add python "$("$PY" --version | cut -d' ' -f2)" '$PY' "scripts of step 07"
add pandas "$("$PY" -c 'import pandas; print(pandas.__version__)')" '$PY' "tables"
add biopython "$("$PY" -c 'import Bio; print(Bio.__version__)')" '$PY' "reading GenBank records of the mitochondrial reference genomes"
add curl "$(curl --version | head -1 | cut -d' ' -f2)" 'system' "download of the mitochondrial reference records through the NCBI Entrez interface"
echo "written: $OUT"
