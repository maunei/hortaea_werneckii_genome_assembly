#!/bin/bash
#SBATCH --job-name=hw_05_polish
#SBATCH --account=<ACCOUNT>
#SBATCH --time=24:00:00
#SBATCH --mem=120G
#SBATCH --cpus-per-task=32
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 05_polish

# Step 05b: consensus polishing with Quiver (GenomicConsensus 2.3.3, algorithm quiver, parameter set of the chemistry P4-C2): the five alignments of step 05a are merged and the contigs are
# polished in one round with default settings. The polished contigs are written to $WORK/asm/<OUTNAME>/polished.fasta; step 05c (jobs/05_remove_contaminant_contigs.sbatch) makes the final assembly from them. Parameters (sbatch --export=ALL,RAW=...,OUTNAME=...): RAW, OUTNAME as in step 05a; THREADS (default: the cores of the job).
RAW=${RAW:?set RAW}; OUTNAME=${OUTNAME:?set OUTNAME}; NT=${THREADS:-${SLURM_CPUS_PER_TASK:-32}}
T="$WORK/polish/$OUTNAME"; OUT="$WORK/asm/$OUTNAME"; R="$RESULTS/05_polish/$OUTNAME"; mkdir -p "$OUT" "$R"; cd "$T" || exit 2
export LD_LIBRARY_PATH="$LEGACY_LIBS:$LD_LIBRARY_PATH"; export PATH="$LEGACY_BIN:$PATH"
for r in SRR5086620 SRR5086623 SRR5086626 SRR5086627 SRR5086628; do [ -s "$r.aligned.bam.pbi" ] || { echo "missing alignment of $r (run jobs/05_align_subreads.sbatch)"; exit 2; }; done
pbmerge -o all.aligned.bam SRR*.aligned.bam > "$LOGDIR/pbmerge.out" 2>&1 || exit 4
/usr/bin/time -v variantCaller --algorithm=quiver -j "$NT" -r ref.fa --verbose -o polished.fasta -o polished.gff all.aligned.bam > "$LOGDIR/quiver.out" 2> "$LOGDIR/quiver.time"; rc=$?
echo "quiver exit $rc"; [ $rc = 0 ] || exit 5
sed 's/^>\([^|]*\)|quiver.*/>\1/' polished.fasta > "$OUT/polished.fasta"
"$QC_BIN/seqkit" stats -a -T "$WORK/asm/$RAW/final.fasta" "$OUT/polished.fasta" > "$R/assembly_stats.tsv" || exit 4; cut -f1-9,13,14 "$R/assembly_stats.tsv"
# number of changes made by Quiver, by type (column 3 of the GFF file)
grep -v '^#' polished.gff | cut -f3 | sort | uniq -c | awk 'BEGIN{OFS="\t"; print "change","count"} {print $2,$1}' > "$R/quiver_changes.tsv"; cat "$R/quiver_changes.tsv"
grep -hE "Elapsed|Maximum resident" "$LOGDIR/quiver.time" > "$R/time_memory.txt"
rm -f all.aligned.bam all.aligned.bam.pbi
hw_end 05_polish
