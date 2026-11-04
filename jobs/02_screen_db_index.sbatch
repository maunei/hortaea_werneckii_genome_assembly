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
PS="$SCREEN_DB/parts_stats.tsv"   # written only when it is missing or older than a part: the databases folder is not written again at every run
if [ ! -s "$PS" ] || [ -n "$(find "$SCREEN_DB" -maxdepth 1 -name '*.fa.gz' -newer "$PS" -print -quit)" ]; then
  "$SCREEN_BIN/seqkit" stats -T -j "${SLURM_CPUS_PER_TASK:-16}" "$SCREEN_DB"/*.fa.gz > "$PS.tmp.$$" && mv "$PS.tmp.$$" "$PS" || exit 4
fi
cat "$PS"
ls -l "$SCREEN_DB"/*.mmi
# small descriptors of the database for results/ (sequences and bases per part, RefSeq release, table linking every key to its organism)
R="$RESULTS/02_pacbio_reads/screen_db"; mkdir -p "$R" || exit 5
sed 's#[^\t]*/##' "$SCREEN_DB/parts_stats.tsv" > "$R/parts_stats.tsv" || exit 5
cp "$SCREEN_DB/refseq_release.txt" "$R/" || exit 5
gzip -c "$SCREEN_DB/screen_manifest.tsv" > "$R/screen_manifest.tsv.gz" || exit 5
hw_end screen_dbindex
