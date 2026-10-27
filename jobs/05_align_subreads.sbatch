#!/bin/bash
#SBATCH --job-name=hw_05_align
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --array=0-4
#SBATCH --output=logs/%x_%A_%a.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 05_align

# Step 05a (one sequencing run per task): subreads of the run that passed the contaminant screen, with their quality-value tracks, aligned to the assembly to be polished (pbalign, a BLASR-based aligner).
# Parameters (sbatch --export=ALL,RAW=...,OUTNAME=...): RAW = assembly to polish (for example proc_r1_raw); OUTNAME = name of the polished assembly (for example proc_r1); THREADS (default: the cores of the task).
RAW=${RAW:?set RAW}; OUTNAME=${OUTNAME:?set OUTNAME}; NT=${THREADS:-${SLURM_CPUS_PER_TASK:-16}}
RUNS=(SRR5086620 SRR5086623 SRR5086626 SRR5086627 SRR5086628); RUN="${RUNS[$SLURM_ARRAY_TASK_ID]}"
T="$WORK/polish/$OUTNAME"; mkdir -p "$T"; cd "$T"; IN="$WORK/asm/$RAW/final.fasta"; [ -s "$IN" ] || { echo "no assembly $IN"; exit 2; }
cp "$IN" ref.fa.tmp.$RUN && { [ -s ref.fa ] || mv ref.fa.tmp.$RUN ref.fa; }; rm -f ref.fa.tmp.$RUN
( flock 9; [ -s ref.fa.fai ] || "$QC_BIN/samtools" faidx ref.fa ) 9> ref.lock
# reads that passed the screen: the high-quality subreads of this run without the reads excluded by the screen (step 02b)
awk 'NR%4==1{print substr($1,2)}' "$WORK/pacbio_bam/$RUN/$RUN.hq_subreads.fastq" | grep -vxFf "$RESULTS/02_pacbio_reads/screen/hq_excluded_reads.txt" > "$RUN.names.txt"
"$QC_BIN/samtools" view -h -b -N "$RUN.names.txt" -o "$RUN.subreads.clean.bam" "$WORK/pacbio_bam/$RUN/$RUN.subreads.bam" || exit 2
export LD_LIBRARY_PATH="$LEGACY_LIBS:$LD_LIBRARY_PATH"; export PATH="$LEGACY_BIN:$PATH"
pbindex "$RUN.subreads.clean.bam" || exit 2
echo "subreads kept: $(wc -l < "$RUN.names.txt")"
/usr/bin/time -v pbalign --nproc "$NT" "$RUN.subreads.clean.bam" ref.fa "$RUN.aligned.bam" > "$LOGDIR/pbalign_$RUN.out" 2> "$LOGDIR/pbalign_$RUN.time"; rc=$?
echo "pbalign exit $rc"; [ $rc = 0 ] || exit 3
rm -f "$RUN.subreads.clean.bam" "$RUN.subreads.clean.bam.pbi"
hw_end 05_align
