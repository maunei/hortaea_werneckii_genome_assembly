#!/bin/bash
# Step 03: write envs/versions_03.tsv with the versions reported by the programs themselves.
module --force purge; module load StdEnv/2023
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
v() { "$@" 2>&1 | head -1 | tr '\t' ' ' | sed -E 's/^[A-Za-z0-9_ -]*[ ,:]+(v?[0-9][0-9.]*)$/\1/; s/^.*version[: ]+//I'; }
{
printf "program\tversion\tenvironment\tpurpose\n"
printf "fasterq-dump (SRA Toolkit)\t%s\tRNA_BIN\tconversion of SRA archive files to FASTQ\n" "$(v "$RNA_BIN/fasterq-dump" --version | sed 's/.*: *//; s/^ *//' | head -1)"
printf "seqkit\t%s\tQC_BIN\tcounting read pairs in the FASTQ files\n" "$(v "$QC_BIN/seqkit" version)"
printf "FastQC\t%s\tQC_BIN\tquality control of all reads\n" "$(v "$QC_BIN/fastqc" --version)"
printf "fastp\t%s\tQC_BIN\treport-only quality, adapter, duplication and insert-size evaluation\n" "$(v "$QC_BIN/fastp" --version)"
printf "MultiQC\t%s\tQC_BIN\tsummary report of all runs\n" "$(v "$QC_BIN/multiqc" --version)"
printf "pigz\t%s\tStdEnv/2023 module\tparallel compression of the FASTQ files\n" "$(v pigz --version)"
printf "Python\t%s\tPY\ttables from the fastp and FastQC outputs (standard library only)\n" "$(v "$PY" --version)"
} > "$HW/envs/versions_03.tsv"
cat "$HW/envs/versions_03.tsv"
