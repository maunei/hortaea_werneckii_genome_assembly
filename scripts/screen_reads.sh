#!/bin/bash
# Contaminant screen of the PacBio read sets (step 02b). For each set the reads are aligned (minimap2, preset map-pb) to the
# screen database; a read is excluded only if contaminant alignments cover most of it and no fungal alignment exists.
# Whole reads are removed or kept; no base is changed.
# Environment variables (defaults in brackets):
#   READS_DIR [$WORK/reads/pacbio]   folder with <set>_subreads.fastq; the clean sets <set>_clean.fastq are written there
#   SETS [hq filtered]               names of the sets
#   OUT_DIR [$RESULTS/02_pacbio_reads/screen]
#   TMP_DIR [$WORK/screen_reads]     alignments (kept; can be deleted afterwards)
#   MARKER [$READS_DIR/READY_02]     file created when all sets are done (empty string: no marker)
#   REQUIRE_MARKER [empty]           if set, the script stops unless this file exists (the production job requires READY_02A)
#   THREADS [SLURM_CPUS_PER_TASK or 8]
set -euo pipefail
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"; source "$HW/scripts/screen_common.sh"
READS_DIR="${READS_DIR:-$WORK/reads/pacbio}"; SETS="${SETS:-hq filtered}"
OUT_DIR="${OUT_DIR:-$RESULTS/02_pacbio_reads/screen}"; TMP_DIR="${TMP_DIR:-$WORK/screen_reads}"
MARKER="${MARKER-$READS_DIR/READY_02}"; THREADS="${THREADS:-${SLURM_CPUS_PER_TASK:-8}}"
if [ -n "${REQUIRE_MARKER:-}" ] && [ ! -e "$REQUIRE_MARKER" ]; then echo "required marker $REQUIRE_MARKER is missing; the read sets are not ready"; exit 2; fi
mkdir -p "$OUT_DIR" "$TMP_DIR"
for part in $SCREEN_PARTS; do [ -s "$SCREEN_DB/$part.mmi" ] || { echo "index $SCREEN_DB/$part.mmi missing (run jobs/02_screen_db_index.sbatch)"; exit 3; }; done
for set in $SETS; do
  fq="$READS_DIR/${set}_subreads.fastq"; [ -s "$fq" ] || { echo "missing $fq"; exit 4; }
  echo "[$(date +'%F %T')] set $set: $fq"
  "$SCREEN_BIN/seqkit" fx2tab -n -l -i -j "$THREADS" "$fq" > "$TMP_DIR/${set}_lengths.tsv"
  screen_map "$fq" map-pb "$TMP_DIR/$set" "$THREADS"
  "$SCREEN_BIN/python" "$HW/scripts/screen_classify.py" --paf "$TMP_DIR/${set}"_*.paf.gz --lengths "$TMP_DIR/${set}_lengths.tsv" \
      --manifest "$SCREEN_DB/screen_manifest.tsv" --outdir "$OUT_DIR" --label "$set" --kind read \
      --min-contam-frac "$MIN_CONTAM_FRAC" --min-aln-len "$MIN_ALN_LEN" --min-identity "$MIN_IDENTITY" --min-identity-contaminant "$MIN_IDENTITY_CONTAM"
  ex="$OUT_DIR/${set}_excluded_reads.txt"; clean="$READS_DIR/${set}_clean.fastq"
  nex=$(wc -l < "$ex")
  rm -f "$clean"
  if [ "$nex" -eq 0 ]; then
    ln -s "$fq" "$clean"; echo "no read excluded in $set: $clean is a symbolic link to $fq"
  else
    "$SCREEN_BIN/seqkit" grep -v -f "$ex" -j "$THREADS" "$fq" -o "$clean"
    nin=$(wc -l < "$TMP_DIR/${set}_lengths.tsv"); nout=$("$SCREEN_BIN/seqkit" stats -T "$clean" | awk 'NR==2{print $4}')
    [ $((nin - nout)) -eq "$nex" ] || { echo "count mismatch for $set: in $nin, out $nout, excluded $nex"; exit 5; }
    echo "$nex reads excluded from $set; $clean written ($nout reads)"
  fi
done
# one file with the counts of all sets and one with the criterion
head -n 1 "$OUT_DIR/$(echo $SETS | cut -d' ' -f1)_counts.tsv" > "$OUT_DIR/counts_by_set.tsv"
for set in $SETS; do tail -n +2 "$OUT_DIR/${set}_counts.tsv" >> "$OUT_DIR/counts_by_set.tsv"; done
cat > "$OUT_DIR/criterion.txt" <<C
Exclusion criterion (fixed in the analysis plan): a read is excluded only if it matches contaminant sequences over most of its length and has no fungal match.
Operational definition used here:
  alignment   : minimap2 preset map-pb, base-level alignment (-c) of each read to the screen database; an alignment counts only if its length is at least ${MIN_ALN_LEN} bases and residue matches / alignment length is at least ${MIN_IDENTITY_CONTAM} for contaminant targets and ${MIN_IDENTITY} for fungal targets.
  contaminant : target sequence of bacteria, archaea, viruses, human (T2T-CHM13v2.0) or vector (UniVec).
  most        : the union of the aligned parts of the read on contaminant targets covers at least ${MIN_CONTAM_FRAC} of the read length.
  fungal match: at least one counted alignment to a fungal target.
  excluded    : contaminant covers at least ${MIN_CONTAM_FRAC} of the read AND no fungal match. All other reads are kept unchanged.
C
[ -z "$MARKER" ] || { touch "$MARKER"; echo "marker $MARKER created"; }
echo "[$(date +'%F %T')] screen of reads finished"
