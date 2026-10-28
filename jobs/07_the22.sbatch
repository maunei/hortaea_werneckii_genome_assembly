#!/bin/bash
#SBATCH --job-name=hw_the22
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=96G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start the22
# Step 07b: the 22 sequences of the GitHub file of Hw 2.0 that are absent from the NCBI record.
# Needs the table of step 07a (results/07_comparator/genbank_files/the22_ids.tsv).
# Parameters (all optional): READS = PacBio reads for the depth (default $WORK/reads/pacbio/hq_clean.fastq; without reads the depth is reported as unavailable);
# FASTA = Hw 2.0 (default $WORK/asm/hw2/final.fasta); OUT = output folder (default results/07_comparator/the22); DEPTH_DIR = folder of the depth of Hw 2.0.
FASTA="${FASTA:-$WORK/asm/hw2/final.fasta}"; READS="${READS:-$WORK/reads/pacbio/hq_clean.fastq}"; THREADS="${SLURM_CPUS_PER_TASK:-8}"
OUT="${OUT:-$RESULTS/07_comparator/the22}"; TMP="$WORK/07_comparator/the22"; mkdir -p "$OUT" "$TMP"
IDS="$RESULTS/07_comparator/genbank_files/the22_ids.tsv"; [ -s "$IDS" ] || { echo "run jobs/07_genbank_files.sbatch first" >&2; exit 1; }
[ -s "$DBS/mito_refs/mito_proteins.faa" ] || bash "$HW/scripts/07_fetch_mito_refs.sh"
[ -s "$DBS/rdna_refs/rdna_hw.fasta" ] && [ -s "$DBS/rdna_refs/vector_marker_bla.faa" ] || bash "$HW/scripts/07_fetch_rdna_refs.sh"
[ -s "$SWISSPROT_FUNGI" ] || { echo "protein set not found: $SWISSPROT_FUNGI (made by scripts/06_fetch_databases.sh)" >&2; exit 1; }
export DEPTH_DIR="${DEPTH_DIR:-$WORK/07_comparator/hw2}"
if [ -s "$READS" ] || [ -s "$DEPTH_DIR/depth.per_contig.tsv" ]; then bash "$HW/scripts/07_depth.sh" hw2 "$FASTA" "$READS" "$THREADS" || exit 1
else echo "reads not found ($READS): the depth is skipped"; unset DEPTH_DIR; fi
[ -s "$RESULTS/07_comparator/mito/hw2/summary.json" ] && export MITO_SUMMARY="$RESULTS/07_comparator/mito/hw2/summary.json"
# Contaminant screen of contigs (scripts/screen_contigs.sh of step 02b), run on the 22 sequences only, in this step's own folders.
# When the screening script or its indexed databases are not present, the notice below is printed and the column reads 'not run'.
SCREEN="${SCREEN_SCRIPT:-$HW/scripts/screen_contigs.sh}"
if [ -f "$SCREEN" ]; then
  "$PY" - <<PYEOF
import sys; sys.path.insert(0, "$HW/scripts"); from hw07_common import *
ids = [l.split("\t")[0] for l in open("$IDS").read().splitlines()[1:]]
a = read_fasta("$FASTA"); write_fasta("$TMP/the22.fa", {n: a[n] for n in ids})
PYEOF
  if ASM=the22_hw2 FASTA="$TMP/the22.fa" OUT_DIR="$OUT/contaminant_screen" TMP_DIR="$WORK/07_comparator/screen_the22" THREADS="$THREADS" bash "$SCREEN" \
     && [ -s "$OUT/contaminant_screen/the22_hw2_per_contig.tsv.gz" ]; then
    export SCREEN_TSV="$OUT/contaminant_screen/the22_hw2_per_contig.tsv.gz"
  else
    echo "hook: the contaminant screen could not be run (indexed databases missing?); the column is reported as 'not run'"
  fi
else
  echo "hook: scripts/screen_contigs.sh not present; the contaminant screen of the 22 sequences is reported as 'not run'"
fi
"$PY" "$HW/scripts/07_the22.py" "$FASTA" "$IDS" "$OUT" "$TMP" "$THREADS"
hw_end the22
