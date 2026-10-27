## Step 03. RNA-seq and Illumina 2013 reads: conversion to FASTQ, read counts and quality control

### What this step does and why

The assembly itself uses only the PacBio reads. Two other data sets are needed by the tests that follow: the RNA-seq reads (two runs, SRR5086621 on a MiSeq instrument and SRR5086622 on a HiSeq instrument, cells grown at 10 % NaCl) and the Illumina genomic reads of 2013 (run SRR866616, 76-base read pairs from the same strain). All three arrive as archive files of the Sequence Read Archive (SRA) in a binary format that the aligners cannot read. This step converts them to FASTQ (the plain-text format of reads and base qualities), proves that no read was lost in the conversion, and measures the quality of the reads, so that every later test starts from files that have been checked.

The step has two jobs:

1. `jobs/03_convert.sbatch` converts one run and compares its number of read pairs with the number written in the archive record; it is submitted once per run.
2. `jobs/03_qc.sbatch` runs the quality control of all runs and writes the summary tables.

### Conversion and counts

Conversion uses `fasterq-dump` of the SRA Toolkit with `--split-3`: the two mates of each pair go to `<RUN>_1.fastq` and `<RUN>_2.fastq`, and any read without a mate would go to a third file (the table records how many, expected: none). The read names are written as `@<RUN>.<spot>/1` and `@<RUN>.<spot>/2` (a spot is one cluster on the flow cell, that is one read pair), so that the two mates of a pair can be matched by name; the job checks that the names in the two files agree line by line. Temporary files are written to the node-local disk of the compute node, because `fasterq-dump` needs several times the size of the final FASTQ files and a local disk is much faster than shared storage. The files are compressed with `pigz` (parallel gzip). Compressed files are first written under the extra extension `.part` and receive their final name only after the counts and the name check pass, so a final `.fastq.gz` file is always a complete and checked file.

The numbers of pairs found are compared with the archive records (175,019,208 for the HiSeq run, 3,333,452 for the MiSeq run, 37,667,637 for the Illumina run). A difference of any size stops the job with an error: a lost read would silently change every later count of reads mapped.

When both RNA runs have passed, the empty marker file `READY_03` is created in the RNA folder of the work area, and when the Illumina run has passed it is created in the Illumina folder; later steps wait for these markers.

```bash
cd "$HW"
sbatch --export=ALL,RUN=SRR5086621,GROUP=rna,EXPECTED=3333452          --time=01:00:00 --cpus-per-task=8  jobs/03_convert.sbatch
sbatch --export=ALL,RUN=SRR5086622,GROUP=rna,EXPECTED=175019208        --time=08:00:00 --cpus-per-task=16 jobs/03_convert.sbatch
sbatch --export=ALL,RUN=SRR866616,GROUP=illumina2013,EXPECTED=37667637 --time=04:00:00 --cpus-per-task=16 jobs/03_convert.sbatch
```

### Quality control

Three programs are used, each answering a different question.

1. FastQC reads every read of every file and reports per-base quality, base composition, adapter content, duplication and over-represented sequences.
2. fastp is run in report-only mode: it receives the two FASTQ files and no output file names, so it writes no reads, only a JSON report (read by the summary script) and an HTML report. It gives the percentage of bases with a Phred quality of at least 30 (Q30; a 1 in 1,000 chance that the base is wrong), the fraction of reads in which an adapter was found by overlap analysis of the two mates, the duplication rate, the GC content and the insert size (the length of the DNA fragment between the adapters, estimated from pairs whose mates overlap).
3. MultiQC collects the FastQC and fastp reports of all runs into one HTML page.

The reads are not trimmed in this step. The aligners used later (STAR and bwa-mem) soft-clip the ends of reads that do not align, and trimming would change the reads that the tests receive. The adapter content found is reported below.

```bash
sbatch --dependency=afterok:<id of the HiSeq conversion>:<id of the Illumina conversion> jobs/03_qc.sbatch
```

### What to expect

- `results/03_rna_illumina/read_counts.tsv`: for each run the pairs of the archive record, the pairs found in each mate file, the reads without a mate, the result of the name check and the status. Every status must read `ok`.
- `results/03_rna_illumina/qc_summary.tsv`: for each run the number of pairs, the mean read length of each mate, the mean base quality of each mate (FastQC), the percentage of bases at Q30 and Q20, the percentage of reads with adapter found (fastp) and the highest adapter percentage at any position (FastQC), the duplication rate, the GC content, the peak of the insert-size distribution and the percentage of pairs whose insert size could not be estimated, and the FastQC modules that failed.
- `results/03_rna_illumina/multiqc_report.html` and `results/03_rna_illumina/fastp/<RUN>.json`.
- HiSeq run: {{results/03_rna_illumina/qc_summary.tsv:SRR5086622 pairs}} pairs, {{results/03_rna_illumina/qc_summary.tsv:SRR5086622 percent_bases_q30_fastp}} % of bases at Q30; MiSeq run: {{results/03_rna_illumina/qc_summary.tsv:SRR5086621 pairs}} pairs; Illumina 2013 run: {{results/03_rna_illumina/qc_summary.tsv:SRR866616 pairs}} pairs.

How to read the quality tables. FastQC marks several modules as failed on almost any RNA-seq or amplified library for reasons that are expected and not defects: the base composition of the first bases of RNA-seq reads is biased by random-hexamer priming, and highly expressed transcripts appear as over-represented sequences and raise the duplication rate. In RNA-seq the duplication rate therefore measures expression depth as much as library complexity; in the genomic Illumina run a high duplication rate would indicate a library of low complexity and would matter for the depth estimates of the later tests.

### Outcome of the quality control

The percentage of reads with adapter found by fastp (column `adapter_trimmed_reads_percent_fastp`) and the highest adapter percentage of FastQC (columns `adapter_max_percent_mate1_fastqc`, `adapter_max_percent_mate2_fastqc`) answer different questions: fastp counts reads in which the two mates overlap beyond the end of the insert, FastQC gives the cumulative percentage of reads carrying adapter sequence by the last position. All three runs have the number of read pairs written in the archive record, and no raw read needed processing before it could be used by the tests. Adapter sequence was found by fastp in {{results/03_rna_illumina/qc_summary.tsv:SRR5086622 adapter_trimmed_reads_percent_fastp}} percent of the HiSeq read pairs, {{results/03_rna_illumina/qc_summary.tsv:SRR5086621 adapter_trimmed_reads_percent_fastp}} percent of the MiSeq pairs and {{results/03_rna_illumina/qc_summary.tsv:SRR866616 adapter_trimmed_reads_percent_fastp}} percent of the Illumina 2013 pairs. The reads were used without trimming because the aligners (STAR and bwa-mem) soft-clip the ends of reads that do not align, so adapter remnants do not change the alignments of the rest of a read; the HiSeq value is the largest and is the one that could matter, and it is reported as a limit of the RNA-seq alignment test. The Illumina 2013 reads have {{results/03_rna_illumina/qc_summary.tsv:SRR866616 percent_bases_q30_fastp}} percent of bases at Q30, lower than the RNA-seq runs; the accuracy test accounts for this by requiring a base quality of 25 and a depth of at least 10 reads. All values of the three runs are in `qc_summary.tsv`.

### Why these settings

- `--split-3` and normalised names: the aligners require the mates in the same order; checking the names once here saves a failure later.
- Counts compared with the archive: this guards against a truncated download or an interrupted conversion, the two commonest silent failures.
- Duplication accuracy level 3 of fastp (about 4 GB of memory for the table of read signatures): the duplication rate is estimated from hashed read signatures, and a higher level uses a larger table, which lowers the number of unrelated reads that are counted as duplicates by chance; this matters for a run of 175 million pairs.
- No trimming: stated above.

Programs and versions are listed in `envs/versions_03.tsv`.
