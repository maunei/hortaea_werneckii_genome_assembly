## Step 09. Summary tables, figures and the assessment of every evaluation

### How an evaluation is judged

For every evaluation the criteria for calling Hw 2.1 better, not worse or worse than Hw 2.0 were fixed before the results were known, and they are applied by `scripts/09_summary.py` without any judgement in between.

| Evaluation | Better if | Not worse if | Worse if |
|---|---|---|---|
| 1. Contiguity | N50, NG50 and auN higher and L50 lower | equal within the noise scale | lower beyond the noise scale |
| 2. Completeness of the gene space | complete BUSCO genes and aligned transcripts higher | equal within the noise scale | lower beyond noise |
| 3. Structure | among the disagreements decided by the reads, more are decided for Hw 2.1 than for Hw 2.0, with a 95 percent interval (Wilson) that excludes one half, in each of the three runs | the interval includes one half | the interval lies below one half |
| 4. Redundancy and collapse | less false duplication and a higher proportion of bases at 0.5 to 1.5 times the median depth | equal within the noise scale | more false duplication or collapse beyond noise |
| 5. Accuracy of the bases | fewer differences specific to one assembly per Mb | equal within the noise scale | more beyond noise |

Hw 2.1 is called better than Hw 2.0 when it is better in evaluation 1 and in at least one other evaluation and is worse in none. If this is not met, the table is reported as it is.

### Noise scale

The three polished runs of the procedure (`proc_r1`, `proc_r2`, `proc_r3`) were made from the same reads with different thread settings. For every measure the **noise scale** is the range (largest minus smallest value) over the three runs: the variation the procedure shows when nothing but the thread count changes. A difference between Hw 2.1 and Hw 2.0 counts as real only when it is larger than this range. In the run reported here the three runs are identical, so the noise scale is practically zero.

### Further tables

`measures.tsv` holds every measure for every assembly. `results_table.tsv` is the table of the report. `scripts/09_resources.py` writes the time and memory of every job from the scheduler records and the `/usr/bin/time` records of the long stages. `scripts/09_replicates.sh` writes the checksums of the corrected reads and of the assemblies of the three runs. `scripts/09_release.py` writes the final assembly as files.

### How to run

`scripts/submit_all.sh` submits this step as its last job (`jobs/09_summary.sbatch`), which runs the five scripts below and the validation of step 10 in order. By hand, from the workflow folder:

```bash
cd $HW
export HW=$PWD RESULTS=$PWD/results
python3 scripts/09_summary.py          # tables, figures, assessment of the evaluations
python3 scripts/09_qc_figures.py       # quality-control figures and statistics of the sequence data
bash scripts/09_replicates.sh          # checksums of the three runs
python3 scripts/09_resources.py        # time and memory of every job
python3 scripts/09_release.py proc_r1  # the final assembly as files
```

### Output files

`results/09_summary/`: `measures.tsv`, `noise_scale.tsv`, `verdict.tsv`, `verdict.json`, `results_table.tsv`, `fig_contigs.png` and `.svg` (contig lengths), `fig_measures.png` and `.svg`, `fig_qc_pacbio`, `fig_qc_illumina` and `fig_qc_depth` (`.png` and `.svg`, quality control of the PacBio reads, the RNA-seq and Illumina reads, the depth over the assemblies and the transcripts), `qc_stats.tsv` (the statistics behind them), `replicate_check.tsv`, `resources_jobs.tsv`, `resources_stages.tsv`, `resources_totals.json`. `results/assembly/`: the final assembly `Hw2.1.fasta.gz` and the table of its contigs `Hw2.1_contigs.tsv`.
