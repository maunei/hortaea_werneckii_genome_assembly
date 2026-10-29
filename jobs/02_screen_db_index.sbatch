#!/bin/bash
#SBATCH --job-name=hw_screen_dbindex
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=128G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start screen_dbindex
# Build one minimap2 index per database part (preset map-pb: k=19, w=10, homopolymer-compressed). -I 100G keeps each part in one index.
source "$HW/scripts/screen_common.sh"
for part in $SCREEN_PARTS; do
  [ -s "$SCREEN_DB/$part.fa.gz" ] || { echo "ERROR: $SCREEN_DB/$part.fa.gz is missing: run the download (stage databases) again" >&2; exit 2; }
  if [ -s "$SCREEN_DB/$part.mmi" ]; then echo "$part.mmi exists, skipped"; continue; fi
  echo "[$(date)] indexing $part"
  "$SCREEN_BIN/minimap2" -x map-pb -t "${SLURM_CPUS_PER_TASK:-16}" -I 100G -d "$SCREEN_DB/$part.mmi.tmp" "$SCREEN_DB/$part.fa.gz" && mv "$SCREEN_DB/$part.mmi.tmp" "$SCREEN_DB/$part.mmi" || exit 3
done
# number of sequences and bases per part (a check of the download)
"$SCREEN_BIN/seqkit" stats -T -j "${SLURM_CPUS_PER_TASK:-16}" "$SCREEN_DB"/*.fa.gz > "$SCREEN_DB/parts_stats.tsv" || exit 4; cat "$SCREEN_DB/parts_stats.tsv"
ls -l "$SCREEN_DB"/*.mmi
hw_end screen_dbindex
