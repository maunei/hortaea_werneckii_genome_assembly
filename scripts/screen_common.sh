# Shared functions of the contaminant screen (source this file after config/config.sh).
# Parameters of the alignment filter and of the criterion (the plan fixes the rule; the numbers are set here once):
export SCREEN_PARTS="${SCREEN_PARTS:-bacteria_1 bacteria_2 other fungi}"
export MIN_ALN_LEN="${MIN_ALN_LEN:-300}"          # alignments shorter than this (bases) are ignored
export MIN_IDENTITY="${MIN_IDENTITY:-0.65}"       # fungal alignments: residue matches / alignment length below this are ignored
export MIN_IDENTITY_CONTAM="${MIN_IDENTITY_CONTAM:-0.70}"   # contaminant alignments: same, stronger evidence (lowers the risk of excluding a fungal read by chance)
export MIN_CONTAM_FRAC="${MIN_CONTAM_FRAC:-0.5}"  # "most of its length": the contaminant alignments must cover at least this fraction

# screen_map QUERY.fa|fq PRESET OUT_PREFIX THREADS : align QUERY to every part of the screen database with minimap2;
# keeps, per alignment passing the filter, the columns: query, query length, query start, query end, target, residue matches, alignment length, mapping quality.
screen_map() {
  local q="$1" preset="$2" outp="$3" thr="$4" part
  for part in $SCREEN_PARTS; do
    echo "[$(date +'%F %T')] aligning to $part"
    "$SCREEN_BIN/minimap2" -x "$preset" -c -t "$thr" -I 100G ${MM_EXTRA:-} "$SCREEN_DB/$part.mmi" "$q" 2> "${outp}_$part.minimap2.log" \
      | awk -F'\t' -v L="$MIN_ALN_LEN" -v I="$MIN_IDENTITY" 'BEGIN{OFS="\t"} $11>=L && $10/$11>=I {print $1,$2,$3,$4,$6,$10,$11,$12}' \
      | "$SCREEN_BIN/pigz" -p 2 > "${outp}_$part.paf.gz"
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "minimap2 failed on $part"; return 1; }
    tail -n 3 "${outp}_$part.minimap2.log"
  done
}
