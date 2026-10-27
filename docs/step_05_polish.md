## Step 05. Polishing with Quiver and removal of contaminant contigs: the final assembly

### What is done and why

The contigs of the assembly of corrected reads still carry errors that were left in the corrected reads. Polishing aligns the raw subreads back to the contigs and recomputes the consensus. The polisher is **Quiver** (GenomicConsensus 2.3.3, algorithm `quiver`), the polishing program of the original HGAP protocol of Chin et al. (2013). It works on the base calls and also on the quality-value tracks that the RS II instrument records for every base (insertion, deletion, substitution and merge quality, and the base that was probably skipped). These tracks are kept by the conversion of step 02a (`bax2bam` is run with the pulse features). Quiver needs the model of the sequencing chemistry; the chemistry of this study, P4-C2, is among the parameter sets of GenomicConsensus 2.3.3, and the parameter set that was used is written in the Quiver log (`P4-C2.AllQVsMergingByChannelModel`).

The subreads used are those that passed the contaminant screen of step 02b: the high-quality subreads of each run without the reads the screen excluded. Quiver is run once, with default settings.

The three runs of the procedure are polished separately (with different thread settings, like step 04), and so are the two control assemblies of step 04, so that the accuracy evaluation can compare polished assemblies with each other.

After polishing, the contaminant screen of step 02b is applied to the contigs and the contigs it excludes are removed (step 05c). The reads were screened before the assembly, but some reads with cloning-vector sequence pass the read screen (it excludes a read only when more than half of it matches contaminant sequence and no part matches fungal sequence), and the contig screen recognises a short contig of vector sequence in the polished assembly. Removing it does not edit any base. The result is the **final assembly**, named Hw 2.1 in this document and `proc_r1`, `proc_r2`, `proc_r3` (the three runs) in file names and commands.

### Steps, in the order in which they are run

1. `jobs/05_align_subreads.sbatch` (an array of five tasks, one per sequencing run): selects the screened subreads from the PacBio BAM file of the run, indexes them (`pbindex`) and aligns them to the assembly to be polished with pbalign.
2. `jobs/05_polish.sbatch`: merges the five alignments (`pbmerge`) and runs `variantCaller --algorithm=quiver`. The polished contigs, with their original names, are written to `$WORK/asm/<OUTNAME>/polished.fasta`; the contig statistics before and after, the number of changes by type and the time and memory go to `results/05_polish/<OUTNAME>/`.
3. `jobs/05_remove_contaminant_contigs.sbatch`: screens the polished contigs (`scripts/screen_contigs.sh`) and writes the final assembly `$WORK/asm/<OUTNAME>/final.fasta` without the excluded contigs; the removed contigs are listed in `results/05_polish/<OUTNAME>/removed_contigs.tsv`.

```bash
cd $HW
sbatch --export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1,THREADS=16 --cpus-per-task=16 jobs/05_align_subreads.sbatch
sbatch --dependency=afterok:<job number of the alignment> --export=ALL,RAW=proc_r1_raw,OUTNAME=proc_r1,THREADS=32 --cpus-per-task=32 jobs/05_polish.sbatch
sbatch --dependency=afterok:<job number of the polishing> --export=ALL,OUTNAME=proc_r1 jobs/05_remove_contaminant_contigs.sbatch
```

Runs 2 and 3 (12 and 24, 8 and 16 threads) and the two controls (`RAW=ctrl_canu,OUTNAME=ctrl_canu_quiver` and `RAW=ctrl_flye,OUTNAME=ctrl_flye_quiver`) are submitted in the same way; `scripts/submit_all.sh` contains all of them with their dependencies.

### Output files

* `results/05_polish/<OUTNAME>/assembly_stats.tsv`: statistics of the assembly before and after polishing.
* `results/05_polish/<OUTNAME>/quiver_changes.tsv`: number of changes Quiver made, by type (insertion, deletion, substitution).
* `results/05_polish/<OUTNAME>/removed_contigs.tsv` and `assembly_stats_after_removal.tsv`: the contigs removed by step 05c and the statistics after their removal.
* `results/05_polish/<OUTNAME>/time_memory.txt`: wall time and peak memory of Quiver.
