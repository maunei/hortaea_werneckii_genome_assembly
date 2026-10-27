## Step 04. The procedure: seeds, correction and assembly; two control assemblies

### The procedure in four stages

The procedure follows the design of the hierarchical genome assembly process (HGAP) of Chin et al. (2013) with current programs where the original ones no longer exist. It is run once with fixed settings; nothing is tuned on the results.

1. **Seeds.** The filtered subreads are sorted by length and the longest are taken until they add up to 30 times the genome size (30 x 50 Mb = 1.5 Gb). The shortest seed is {{results/04_procedure/proc_r1/seeds_stats.tsv:seeds.fa min_len|int}} bases. These {{results/04_procedure/proc_r1/seeds_stats.tsv:seeds.fa num_seqs|int}} reads are the templates for the correction.
2. **Correction.** All filtered subreads are aligned to the seeds with BLASR (up to 24 alignments per read, minimum exact match 12), and a consensus is computed for every seed from the reads aligned to it with pbdagcon (at least 4 reads covering, corrected reads of at least 500 bases). The result is a set of corrected reads, each the consensus of several raw reads, with a much lower error rate than a raw subread.
3. **Assembly.** Canu is run in assembly-only mode on the corrected reads, with the maximum error rate between two corrected reads set to 0.025 (2.5 percent), the value suited to corrected reads. Canu's own correction and trimming are not used.
4. **Polishing (step 05).** The contigs are polished with Quiver, the polisher of the original protocol, which uses the quality-value tracks of the sequencing instrument.

### Why the correction is expected to help, and what it is compared with

This is the hypothesis the tests examine, not a result. Many regions of this genome occur in two copies that differ by a few percent: in Hw 2.0, {{results/06_tests/hw2/summary.json:busco.duplicated_percent|.1f}} percent of the conserved fungal genes (BUSCO) are found in two copies. An assembler that tolerates the 15 percent error of a raw subread in an overlap cannot always tell a true overlap from the overlap of two similar copies, and the assembly graph then breaks or merges at those places. After correction against the longest reads, the error of each corrected read is small enough that the copies can be separated. Two **control assemblies** show what the two assemblers give without this step, from the same filtered reads and the same genome size of 50 Mb: Canu with its default settings and its own correction (`ctrl_canu`), and Flye with default settings (`ctrl_flye`, which includes Flye's own default polishing). Both controls are also polished with Quiver in step 05 (`ctrl_canu_quiver`, `ctrl_flye_quiver`), so that they can be compared with the polished assemblies of the procedure on the accuracy of the bases. The like-for-like comparison for the effect of the correction is `ctrl_canu` against `proc_r1_raw`, the first run before polishing, and `ctrl_canu_quiver` against `proc_r1`, both after polishing.

### Three runs for the noise scale

The procedure is run three times from the same reads, with 16, 12 and 8 threads (`proc_r1`, `proc_r2`, `proc_r3`, named after their polished assemblies). Multithreaded programs can return different results from the same input, and the spread of any measure over the three runs is the noise scale against which differences from Hw 2.0 are judged (step 09). The raw assembly of each run (before polishing) is kept as `proc_r<N>_raw`; the tests are run on that of the first run.

### How to run

```bash
cd $HW
sbatch --export=ALL,RUN=r1,THREADS=16 jobs/04_procedure.sbatch
sbatch --export=ALL,RUN=r2,THREADS=12 --cpus-per-task=12 jobs/04_procedure.sbatch
sbatch --export=ALL,RUN=r3,THREADS=8  --cpus-per-task=8  jobs/04_procedure.sbatch
sbatch jobs/04_control_canu.sbatch
sbatch jobs/04_control_flye.sbatch
```

The raw assembly of each run is `$WORK/asm/proc_<RUN>_raw/final.fasta`; the statistics of every stage are in `results/04_procedure/proc_<RUN>/` (`reads_stats.tsv`, `seeds_stats.tsv`, `corrected_stats.tsv`, `assembly_stats.tsv`). The settings are at the top of `jobs/04_procedure.sbatch` (`SEEDCOV=30`, genome size from `config/config.sh`).

The time and memory of each stage come from the `/usr/bin/time -v` records in `logs/` and are tabulated by `scripts/09_resources.py` in step 09.
