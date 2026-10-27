## Step 08. Illumina reads of 2013: genotype check and base accuracy

### What is measured and why

The Illumina reads of 2013 (accession SRR866616) were produced from the same strain as the PacBio reads, but in another laboratory and at another time. Because their errors are independent of the PacBio errors, they can show where an assembly is wrong at the level of single bases and of short insertions and deletions. The step has two parts that use the same alignment: a genotype check, which asks whether the reads may be used at all, and the base accuracy of each assembly.

Every assembly is tested with the same code. All read pairs are aligned with bwa-mem (the Burrows-Wheeler Aligner, maximal exact match algorithm), the alignments are sorted, and nothing is removed or edited: no read is trimmed or masked, duplicates are not marked, and the reads never change the assembly.

**Callable positions.** A position is callable when the number of reads covering it, counting only reads with mapping quality at least 30, is at least 10 and at most twice the median depth of the windows of 1 kb of that assembly. The lower limit keeps positions where 90 percent of the reads is a meaningful statement; the upper limit removes positions where reads of several copies are piled on one place (collapsed or repeated sequence), where a base that differs from the assembly may come from another copy. Differences are counted per megabase (Mb, one million bases) of callable sequence, so that assemblies with different amounts of unusable sequence are comparable.

**Differences.** A position is a difference when at least 90 percent of the reads (mapping quality at least 30, base quality at least 25, read depth at least 10) carry another base, or an insertion or deletion, instead of the assembly base. The positions are found with the haploid calling mode of bcftools (the program of the samtools family for variant calling); calls with a quality (QUAL) below 30 are dropped, and the 90 percent rule is applied to the allele counts of each call. The genome of this fungus is treated as haploid for this purpose, so a position where the reads are about half and half is not a difference; the number of such calls is reported as `differences.partial_sites_below_threshold`. Insertions and deletions are written in their left-aligned form so that the same event has the same position in all assemblies.

**Single bases and insertions or deletions.** Counts and counts per Mb of callable sequence are given separately for single-base differences, insertions, and deletions. For single-base differences the table of the twelve possible changes (assembly base to read base) is given, together with the six classes with a pyrimidine as reference base and the ratio of transitions (changes within the purines or within the pyrimidines) to transversions. For insertions and deletions the length is tabulated, and each event is marked as lying in a homopolymer when the inserted or deleted sequence is one repeated base and the assembly carries at least 3 identical bases of that base at the site. Long-read assemblies are known to lose or gain bases in homopolymers, so this table tells whether the remaining errors are of that kind.

### Genotype check

The check is the first thing to read, because the accuracy evaluation would be dropped if the reads do not belong to the genotype of the PacBio data. It rests on three observations, all for each assembly:

1. The fraction of read pairs that map (`mapping.percent_mapped`, `mapping.percent_properly_paired`, `mapping.percent_mapq_ge_30`) and the mismatch rate per mapped base (`mapping.mismatch_rate_per_base`). Reads of another genotype map less well and mismatch more.
2. The density of differences per Mb of callable sequence (`genotype_check.differences_per_mb_callable`).
3. The arrangement of the differences along the contigs. Differences caused by random errors of the assembly are spread over the whole sequence; differences caused by another genotype or by a wrongly merged region come in clusters. The table `windows_10kb.tsv` gives the counts in windows of 10 kb. In `summary.json`, `genotype_check.arrangement` holds: the fraction of differences with another difference within 1 kb, the mean and the dispersion index (variance divided by mean; close to 1 for a uniform scatter) of the counts per window, the fraction of windows without difference, and the largest count. Each number is given for the observed differences and for two expectations obtained by placing the same number of differences 200 times at random on callable positions: spread over the whole assembly (`expected_uniform_genome`), and spread within each contig with the observed count of that contig (`expected_uniform_within_contigs`). The second expectation removes the differences in density between contigs and shows whether clustering exists inside contigs. For every number, `mean`, `sd` and `p_ge_observed` (the fraction of replicates, counting the observed one, that reach the observed value) are given; with 200 replicates the smallest possible value is about 0.005.

The contigs with the highest density are listed in `genotype_check.top_contigs_by_density` (contigs with at least `min_callable_bp_for_ranking` callable bases, ten contigs) and for all contigs in `per_contig.tsv`. Windows used for the arrangement are full windows of 10 kb with at least half of their positions callable.

There is no numerical threshold for the check; the outcome is a reading of these numbers, written with the results.

### Shared differences

The two assemblies (Hw 2.0 and Hw 2.1) are made from the same PacBio reads and are compared here with the same Illumina reads. When the Illumina reads disagree with both assemblies at the same place, in the same way, the assembly procedures cannot be blamed: both assemblies carry what the PacBio reads say, and the Illumina reads say something else. The reason is either a real difference between the two cultures of the strain that were sequenced (the Illumina reads are from another culture, sequenced at another time) or a systematic error of the PacBio data. These shared differences are listed separately and are left out of the comparison, which rests on the differences specific to one assembly. The script `scripts/shared_differences.py` takes the differences and the FASTA files of two assemblies and finds the same difference in both by its context:

1. For each single-base difference, the 41 assembly bases centred on the site are taken (20 on each side), with the assembly base and the base found in the reads.
2. The description is written in its canonical orientation: the forward description and the reverse-complement description are compared and the smaller is kept, so that a difference on opposite strands in the two assemblies is still recognised.
3. Two differences are the same when the descriptions are identical (exact match, including the base of the reads).
4. Insertions and deletions use the same rule with 20 assembly bases on each side of the inserted or deleted sequence.

A difference is untestable when its window leaves the contig or holds an undefined base (N). A difference is specific when no description of the other assembly equals it; this includes sites where the other assembly has a different sequence nearby (another difference inside the window makes the description different) and sites where the other assembly lacks the region or the site is not callable there. Specific counts are therefore an upper bound of the true assembly-specific differences. Descriptions that occur more than once in a list (repeated sequence) are flagged in the columns `key_multiplicity_*`; the number of such differences is given in `ambiguous_key`.

### How to run

Index, mapping and calling of one assembly (the time of each stage is written to `timing.tsv`):

```bash
cd $HW
sbatch --export=ALL,ASM=proc_r1,FASTA=$WORK/asm/proc_r1/final.fasta jobs/08_illumina_accuracy.sbatch
```

Without a scheduler, from the package folder: `ASM=proc_r1 FASTA=$WORK/asm/proc_r1/final.fasta SLURM_CPUS_PER_TASK=8 bash jobs/08_illumina_accuracy.sbatch`.

Shared differences of two assemblies, after both have been processed:

```bash
sbatch --export=ALL,ASM_A=proc_r1,ASM_B=hw2 jobs/08_shared_differences.sbatch
```

The job refuses to start when the marker file of step 03 (`READY_03`) is not in the read folder.

### Expected output

For each assembly, the folder `results/08_illumina_accuracy/<ASM>/` holds:

| File | Content |
|---|---|
| `summary.json` | Key numbers (dotted keys such as `differences.per_mb_callable.snv`): mapping statistics, callable bases, counts and densities of differences, substitution classes, indel table, genotype check |
| `differences.tsv` | One row per difference: contig, position, type (`snv`, `ins`, `del`, `complex`), alleles, read counts, fraction of reads that differ, quality, homopolymer mark and run length |
| `per_contig.tsv` | Length, callable bases, mean depth and counts of differences for each contig |
| `windows_10kb.tsv` | Counts in windows of 10 kb of assembly coordinates (single bases and others) with callable bases and an eligibility mark |
| `substitution_types.tsv`, `indel_lengths.tsv` | The two tables of the types and lengths |
| `depth_limits.json`, `timing.tsv` | Median window depth and the depth limits used; time of each stage |

The large files (sorted alignments, callable intervals, raw calls) stay in `$WORK/map/illumina2013/<ASM>/`. The shared differences are written to `results/08_illumina_accuracy/shared/<ASM_A>_vs_<ASM_B>/` (`counts.tsv`, `summary.json`, and one status table per assembly).

Results are quoted from the tables, for example the density of single-base differences of an assembly: {{results/08_illumina_accuracy/proc_r1/summary.json:differences.per_mb_callable.snv}}; the specific differences per Mb: {{results/08_illumina_accuracy/shared/proc_r1_vs_hw2/summary.json:assemblies.proc_r1.specific_per_mb_callable.all}}.

### Settings and their reasons

| Setting | Value | Reason |
|---|---|---|
| Mapping quality | at least 30 | Reads that map equally well to several places are not used |
| Base quality | at least 25 | Removes most sequencing errors of the Illumina reads |
| Depth | 10 to twice the median window depth | See the callable positions above |
| Fraction of reads that differ | at least 0.9 | A fixed difference of a haploid genome; mixtures are not counted |
| Call quality | at least 30 | Standard filter of bcftools calls |
| Homopolymer | at least 3 identical bases | Class used in this step |
| Windows | 10 kb (arrangement), 1 kb (depth, nearness) | Scale of clusters and of copy-number change |

Base-quality recalibration of the alignments (BAQ, the base alignment quality of samtools) is left at the default of bcftools. These values can be changed only through the optional variables named in the head of the job script; they exist to test on a subsample (for example a lower depth limit) and the production runs use the values above.

### Limits

Differences in the first and last 20 bases of a contig cannot be matched in the shared-differences step. Differences lying in regions with a real second copy at 90 to 99 percent identity can be missing, because reads of the other copy lower the mapping quality; the callable-position rule removes most of these sites. No difference is called where the depth is outside the limits, so the density is stated for callable sequence only.
