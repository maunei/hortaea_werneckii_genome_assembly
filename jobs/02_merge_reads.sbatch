#!/bin/bash
#SBATCH --job-name=hw_02_merge_reads
#SBATCH --account=<ACCOUNT>
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 02_merge_reads

# Step 02a (second part): the two read sets of the assemblers, merged over the five movies, and their statistics. The marker READY_02A tells
# the contaminant screen (step 02b) that the sets exist.
O="$WORK/reads/pacbio"; R="$RESULTS/02_pacbio_reads"; mkdir -p "$O" "$R"; cd "$O"
rm -f hq_subreads.fastq filtered_subreads.fastq READY_02A
for RUN in SRR5086620 SRR5086623 SRR5086626 SRR5086627 SRR5086628; do
  cat "$WORK/pacbio_bam/$RUN/$RUN.hq_subreads.fastq" >> hq_subreads.fastq; cat "$WORK/pacbio_bam/$RUN/$RUN.filtered_subreads.fastq" >> filtered_subreads.fastq
done
"$QC_BIN/seqkit" stats -a -T -j 4 hq_subreads.fastq filtered_subreads.fastq > "$R/merged_seqkit_stats.tsv"
cut -f1,4,5,8,9,13 "$R/merged_seqkit_stats.tsv"
touch READY_02A
hw_end 02_merge_reads
