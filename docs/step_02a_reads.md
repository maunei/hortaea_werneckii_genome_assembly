## Step 02a. PacBio reads: conversion, the two read sets and a comparison with the authors' file

### What is made and why

The assembler of the paper started from the subreads of the five runs. A *subread* is one pass of the polymerase around the circular template of one sequencing well (a zero-mode waveguide, ZMW). The `.bax.h5` files hold, for every well, the whole polymerase read and the positions of the high-quality region; adapters are cut out when subreads are made.

Two read sets are made, because the procedure uses them for different purposes.

1. **The high-quality set (`hq`).** All subreads from the high-quality region of every productive well, converted with `bax2bam` (version listed in the software table) and written as FASTQ. It is used where every read helps: polishing and the read-based tests of the assemblies.
2. **The filtered set (`filtered`).** The subreads of the `hq` set that pass the default read filter of the original protocol: the well is productive, the polymerase read score is at least 0.80, and the subread is at least 500 bases long. It is used for the seeds, for the correction and for the control assemblies. The filter is applied by `scripts/filter_subreads.py`, which reads the metrics of the wells from the `.bax.h5` files.

The two sets contain {{results/02_pacbio_reads/merged_seqkit_stats.tsv:hq_subreads.fastq num_seqs|int}} and {{results/02_pacbio_reads/merged_seqkit_stats.tsv:filtered_subreads.fastq num_seqs|int}} subreads, and {{results/02_pacbio_reads/merged_seqkit_stats.tsv:hq_subreads.fastq sum_len|Gb}} and {{results/02_pacbio_reads/merged_seqkit_stats.tsv:filtered_subreads.fastq sum_len|Gb}} Gb (N50 {{results/02_pacbio_reads/merged_seqkit_stats.tsv:hq_subreads.fastq N50|int}} and {{results/02_pacbio_reads/merged_seqkit_stats.tsv:filtered_subreads.fastq N50|int}} bases). Divided by the genome size of 50 Mb used throughout, that is about 56-fold and 37-fold depth.

The scraps (parts of the polymerase reads outside the high-quality regions) are not kept.

### Comparison with the authors' file

The authors deposited the filtered subreads they used as FASTQ (accession SRR5086624, file `Hw_PacBio.filtered_subreads.fastq.bz2`). `scripts/compare_deposited_fastq.py` compares it with the filtered set made here, read by read, by well number and subread coordinates. {{results/02_pacbio_reads/deposited_fastq_comparison.json:holes_in_both|int}} of the {{results/02_pacbio_reads/deposited_fastq_comparison.json:holes_ours|int}} wells of the set made here are in the deposited file, {{results/02_pacbio_reads/deposited_fastq_comparison.json:identical_reads|int}} reads are identical, and {{results/02_pacbio_reads/deposited_fastq_comparison.json:only_ours_same_start_one_contains_other|int}} reads differ only in the end coordinate of the last subread of a well (one base), the sequence of one being contained in the other. The set made here has one extra well with one read. The two sets are therefore the same data for all practical purposes, and the set made here is used because it can be remade from the raw files by anyone.

### How to run

```bash
cd $HW
sbatch --array=0-4 jobs/02_pacbio_reads.sbatch      # one task per sequencing run (movie)
sbatch jobs/02_merge_reads.sbatch                    # merge the five runs into the two read sets
sbatch jobs/02_compare_deposited.sbatch              # optional comparison with the deposited file
```

### Output files

* `results/02_pacbio_reads/<RUN>_seqkit_stats.tsv`, `<RUN>_bax_metrics.json`: read statistics and well metrics of each run.
* `results/02_pacbio_reads/merged_seqkit_stats.tsv`: statistics of the two merged sets (the reads themselves are kept in the work folder).
* `results/02_pacbio_reads/deposited_fastq_comparison.json`: the comparison above.
