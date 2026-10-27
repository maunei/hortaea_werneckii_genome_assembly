#!/bin/bash
# Contaminant screen of the contigs of one assembly (step 02b), same criterion as for reads.
# Usage: ASM=hw2 FASTA=$WORK/asm/hw2/final.fasta bash scripts/screen_contigs.sh
# Output: $RESULTS/02_pacbio_reads/screen_contigs/<ASM>/ : <ASM>_per_contig.tsv.gz (fraction of each contig on fungi and on each
#   contaminant group, best contaminant organism, class), <ASM>_counts.tsv, <ASM>_excluded_contigs.txt, <ASM>_criterion.json.
# Contigs are aligned with the preset asm20 (accurate sequences, up to 20 % divergence) to the same database as the reads.
set -euo pipefail
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"; source "$HW/scripts/screen_common.sh"
: "${ASM:?set ASM}"; : "${FASTA:?set FASTA}"
THREADS="${THREADS:-${SLURM_CPUS_PER_TASK:-8}}"
OUT_DIR="${OUT_DIR:-$RESULTS/02_pacbio_reads/screen_contigs/$ASM}"; TMP_DIR="${TMP_DIR:-$WORK/screen_contigs/$ASM}"
mkdir -p "$OUT_DIR" "$TMP_DIR"; [ -s "$FASTA" ] || { echo "missing $FASTA"; exit 4; }
for part in $SCREEN_PARTS; do [ -s "$SCREEN_DB/$part.mmi" ] || { echo "index $SCREEN_DB/$part.mmi missing"; exit 3; }; done
"$SCREEN_BIN/seqkit" fx2tab -n -l -i "$FASTA" > "$TMP_DIR/lengths.tsv"
MM_EXTRA="${MM_EXTRA:--H}"
screen_map "$FASTA" asm20 "$TMP_DIR/$ASM" "$THREADS"
"$SCREEN_BIN/python" "$HW/scripts/screen_classify.py" --paf "$TMP_DIR/${ASM}"_*.paf.gz --lengths "$TMP_DIR/lengths.tsv" \
    --manifest "$SCREEN_DB/screen_manifest.tsv" --outdir "$OUT_DIR" --label "$ASM" --kind contig \
    --min-contam-frac "$MIN_CONTAM_FRAC" --min-aln-len "$MIN_ALN_LEN" --min-identity "$MIN_IDENTITY" --min-identity-contaminant "$MIN_IDENTITY_CONTAM"
echo "[$(date +'%F %T')] screen of contigs of $ASM finished"
