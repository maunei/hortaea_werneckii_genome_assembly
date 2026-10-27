#!/bin/bash
#SBATCH --job-name=hw_07_compare_adjudicate
#SBATCH --account=<ACCOUNT>
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 07_compare_adjudicate

# Step 07, part 2: the structural disagreements between two assemblies (A and B) and the PacBio reads as referee.
# Parameters (environment variables): A_ASM, B_ASM = names of the two assemblies; FASTA_A, FASTA_B = their FASTA files (default $WORK/asm/<name>/final.fasta);
#   READS = the PacBio reads used as referee (default $WORK/reads/pacbio/hq_clean.fastq, the high-quality subreads after the contaminant screen);
#   OUT = result folder (default $RESULTS/07_compare/<A_ASM>_vs_<B_ASM>).
# Example: sbatch --export=ALL,A_ASM=proc_r3,B_ASM=hw2 jobs/07_compare_adjudicate.sbatch
: "${A_ASM:?set A_ASM}"; : "${B_ASM:?set B_ASM}"
FASTA_A="${FASTA_A:-$WORK/asm/$A_ASM/final.fasta}"; FASTA_B="${FASTA_B:-$WORK/asm/$B_ASM/final.fasta}"
READS="${READS:-$WORK/reads/pacbio/hq_clean.fastq}"
READS_TAG="${READS_TAG:-hq_clean}"          # names the read set in the file names of the cached alignments
OUT="${OUT:-$RESULTS/07_compare/${A_ASM}_vs_${B_ASM}}"
PRESET="${PRESET:-asm10}"                   # minimap2 preset for the alignment of assembly to assembly (see below)
MIN_SV="${MIN_SV:-1000}"; MIN_PIECE="${MIN_PIECE:-5000}"
CPUS="${SLURM_CPUS_PER_TASK:-16}"
for f in "$FASTA_A" "$FASTA_B" "$READS"; do [ -s "$f" ] || { echo "ERROR: $f is missing or empty" >&2; exit 2; }; done
AL="$WORK/aln/07_compare/${A_ASM}_vs_${B_ASM}"; RD="$WORK/aln/07_reads"; mkdir -p "$AL" "$RD" "$OUT"
MM="$QC_BIN/minimap2"; "$MM" --version

# 1. Assembly A against assembly B. Both assemblies come from the same reads, so they differ by less than about one percent in the aligned parts:
#    preset asm10 (up to about 1 percent divergence) rather than asm5 (up to about 0.1 percent), because assemblies that are not polished (the first run before polishing)
#    carry more differences. -c writes the base-level alignment, --secondary=no keeps for each part of A only its best place in B.
"$MM" -x "$PRESET" -c --secondary=no -t "$CPUS" "$FASTA_B" "$FASTA_A" > "$AL/A_to_B.paf" 2> "$LOGDIR/minimap2_asm.log"
echo "alignment records: $(wc -l < "$AL/A_to_B.paf")"

# 2. The disagreements (definitions in the header of the script).
"$PY" "$HW/scripts/07_find_disagreements.py" "$AL/A_to_B.paf" "$A_ASM" "$B_ASM" "$AL/events.tsv" --min-sv "$MIN_SV" --min-piece "$MIN_PIECE" --stats "$AL/alignment_stats.json" || exit 3

# 3. The reads against each assembly (kept for later comparisons that use the same assembly and the same reads).
for X in A B; do
  if [ "$X" = A ]; then ASMX="$A_ASM"; FX="$FASTA_A"; else ASMX="$B_ASM"; FX="$FASTA_B"; fi
  C="$RD/${READS_TAG}_to_${ASMX}.tsv.gz"
  if [ -s "$C" ] && [ "$C" -nt "$FX" ] && [ "$C" -nt "$READS" ] && [ -z "${FORCE:-}" ]; then echo "reusing $C"; continue; fi
  "$MM" -x map-pb -c --secondary=no -t "$CPUS" "$FX" "$READS" 2> "$LOGDIR/minimap2_reads_$X.log" | "$PY" "$HW/scripts/07_compact_read_alignments.py" 200 500 | gzip > "$C.tmp" && mv "$C.tmp" "$C" || exit 4
  echo "$C: $(zcat "$C" | wc -l) alignment records"
done

# 4. The reads decide.
"$PY" "$HW/scripts/07_adjudicate.py" "$AL/events.tsv" "$RD/${READS_TAG}_to_${A_ASM}.tsv.gz" "$RD/${READS_TAG}_to_${B_ASM}.tsv.gz" "$FASTA_A" "$FASTA_B" "$A_ASM" "$B_ASM" "$OUT" || exit 5
cp "$AL/alignment_stats.json" "$OUT/alignment_stats.json"
hw_end 07_compare_adjudicate
