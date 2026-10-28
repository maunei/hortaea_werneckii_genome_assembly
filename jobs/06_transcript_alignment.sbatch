#!/bin/bash
#SBATCH --job-name=hw_06_transcript_alignment
#SBATCH --account=<ACCOUNT>
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=8
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 06_transcript_alignment

# Step 06, part 2: alignment of the de novo transcripts (Trinity, assembled without any genome) to one assembly.
# Parameters (environment variables): ASM = name of the assembly; FASTA = its nucleotide FASTA (default $WORK/asm/$ASM/final.fasta);
#   TRANSCRIPTS = the transcripts (default $WORK/trinity/Trinity.fasta); OUT = result folder (default $RESULTS/06_transcripts/$ASM).
# Example: sbatch --export=ALL,ASM=hw2 jobs/06_transcript_alignment.sbatch
: "${ASM:?set ASM (assembly name)}"
FASTA="${FASTA:-$WORK/asm/$ASM/final.fasta}"
TRANSCRIPTS="${TRANSCRIPTS:-$WORK/trinity/Trinity.fasta}"
OUT="${OUT:-$RESULTS/06_transcripts/$ASM}"
CPUS="${SLURM_CPUS_PER_TASK:-8}"
MAX_INTRON="${MAX_INTRON:-5000}"       # longest intron allowed, the same limit as for the RNA read alignment of step 06 (STAR)
for f in "$FASTA" "$TRANSCRIPTS"; do [ -s "$f" ] || { echo "ERROR: $f is missing or empty" >&2; exit 2; }; done
AL="$WORK/aln/06_transcripts/$ASM"; mkdir -p "$AL" "$OUT"

# minimap2 in splice mode:
#   -x splice      alignment of transcripts to a genome, with introns (long deletions in the genome-side sequence) scored by their splice signals
#   -G $MAX_INTRON the longest intron (5,000 bases, long for a fungal intron)
#   -u b           look for the splice signal GT-AG on both strands, because Trinity transcripts have an arbitrary orientation (the reads are not strand-specific)
#   -c             write the base-level alignment (cigar) and the edit distance NM, which the identity is computed from
#   --secondary=no only the best alignment of each part of a transcript (primary and supplementary pieces)
"$QC_BIN/minimap2" --version
"$QC_BIN/minimap2" -x splice -G "$MAX_INTRON" -u b -c --secondary=no -t "$CPUS" "$FASTA" "$TRANSCRIPTS" > "$AL/transcripts.paf" 2> "$LOGDIR/minimap2.log"
tail -3 "$LOGDIR/minimap2.log"
echo "alignment records: $(wc -l < "$AL/transcripts.paf")"

"$PY" "$HW/scripts/06_transcript_align_stats.py" "$TRANSCRIPTS" "$AL/transcripts.paf" "$AL/$ASM" "$ASM" || exit 3
cp "$AL/$ASM.summary.json" "$OUT/summary.json"
cp "$AL/$ASM.transcripts.tsv.gz" "$OUT/transcripts.tsv.gz"
hw_end 06_transcript_alignment
