#!/bin/bash
#SBATCH --job-name=hw_02_pacbio_reads
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:30:00
#SBATCH --mem=12G
#SBATCH --cpus-per-task=4
#SBATCH --array=0-4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 02_pacbio_reads

# Step 02a, one SMRT movie per task (three .bax.h5 files): subreads clipped to their high-quality region with bax2bam, FASTQ of all of them (set hq),
# FASTQ after the default read filter of the original protocol (set filtered), metrics from the .bax.h5 files.
RUNS=(SRR5086620 SRR5086623 SRR5086626 SRR5086627 SRR5086628); RUN="${RUNS[$SLURM_ARRAY_TASK_ID]}"
echo "Task: ${SLURM_ARRAY_TASK_ID} / Run: ${RUN}"
B="$INPUT/pacbio/$RUN"; O="$WORK/pacbio_bam/$RUN"; R="$RESULTS/02_pacbio_reads"; mkdir -p "$O" "$R"; cd "$O"
BAX=$(ls "$B"/*.bax.h5 | tr '\n' ' ')
"$HDF5_BIN/bax2bam" $BAX --subread --pulsefeatures=DeletionQV,DeletionTag,InsertionQV,IPD,MergeQV,SubstitutionQV,PulseWidth,SubstitutionTag -o "$RUN" > "$LOGDIR/bax2bam_$RUN.log" 2>&1 || exit 2
"$QC_BIN/samtools" fastq -@ 4 "$RUN.subreads.bam" > "$RUN.hq_subreads.fastq" 2> "$LOGDIR/samtools_fastq_$RUN.log" || exit 3
"$PY" "$HW/scripts/filter_subreads.py" "$RUN.hq_subreads.fastq" "$RUN.filtered_subreads.fastq" $BAX > "$LOGDIR/filter_$RUN.log" 2>&1 || exit 4
"$PY" "$HW/scripts/bax_metrics.py" "$R/${RUN}_bax_metrics.json" $BAX > "$LOGDIR/metrics_$RUN.log" 2>&1 || exit 5
"$QC_BIN/seqkit" stats -a -T -j 4 "$RUN.hq_subreads.fastq" "$RUN.filtered_subreads.fastq" > "$R/${RUN}_seqkit_stats.tsv" 2>> "$LOGDIR/seqkit_$RUN.log" || exit 6
rm -f "$RUN.scraps.bam" "$RUN.scraps.bam.pbi"    # the parts outside the high-quality regions are not used (they can be re-made with bax2bam)
cat "$LOGDIR/filter_$RUN.log"
hw_end 02_pacbio_reads
