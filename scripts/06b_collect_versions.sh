#!/bin/bash
# Writes envs/versions_06b.tsv: the programs of steps 06 (de novo transcripts) and 07 (comparison of two assemblies), with versions read from the environments.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
pkg() { ls "$1/conda-meta" 2>/dev/null | grep -E "^$2-[0-9]" | head -1 | sed -E "s/^$2-//; s/\.json$//" | sed -E 's/-[^-]+-[^-]+$//; t; s/-[^-]+$//'; }
{
printf 'program\tversion\tenvironment\tpurpose\n'
printf 'Trinity\t%s\tTRINITY_BIN\tde novo assembly of transcripts from RNA-seq reads without a genome (step 06)\n' "$(pkg "${TRINITY_BIN%/bin}" trinity)"
printf 'Jellyfish\t%s\tTRINITY_BIN\tk-mer counting inside Trinity\n' "$(pkg "${TRINITY_BIN%/bin}" jellyfish)"
printf 'Samtools (Trinity environment)\t%s\tTRINITY_BIN\tused inside Trinity\n' "$(pkg "${TRINITY_BIN%/bin}" samtools)"
printf 'Bowtie2\t%s\tTRINITY_BIN\tused inside Trinity\n' "$(pkg "${TRINITY_BIN%/bin}" bowtie2)"
printf 'minimap2\t%s\tQC_BIN\talignment of transcripts to assemblies (splice mode), of assembly to assembly (asm10), of PacBio reads (map-pb); steps 06 and 07\n' "$("$QC_BIN/minimap2" --version)"
printf 'Python\t%s\tPY\tscripts of steps 06 and 07 (standard library only)\n' "$("$PY" --version 2>&1 | sed 's/Python //')"
} > "$HW/envs/versions_06b.tsv"
cat "$HW/envs/versions_06b.tsv"
