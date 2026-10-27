## Step 07b: comparing two assemblies, with the PacBio reads as referee

### What this step answers

Two assemblies built from the same reads can differ in structure: one has joined two pieces that the other keeps apart, one carries a segment that the other lacks, one has a stretch in the opposite orientation. Contiguity statistics (N50, number of contigs) cannot tell which of the two is right; a wrong join raises N50 just as a right one does. The reads can: each PacBio read is a piece of the real genome, so a read that crosses the place where the assemblies differ shows which arrangement the genome has.

This step lists every such difference between assembly A and assembly B and counts, for each, the reads that agree with A, the reads that agree with B and the reads that agree with neither. A difference is decided when at least 3 reads span it. The result is the proportion of the differences that the reads decide for A and for B.

### Commands

Script: `jobs/07_compare_adjudicate.sbatch`. One run compares one pair; the order of the pair only decides which assembly is called A.

```bash
sbatch --export=ALL,A_ASM=proc_r3,B_ASM=hw2 jobs/07_compare_adjudicate.sbatch
```

The assemblies are read from `$WORK/asm/<name>/final.fasta`, the reads from `$WORK/reads/pacbio/hq_clean.fastq` (the high-quality subreads after the contaminant screen). The base-level alignments of the reads to each assembly are kept in `$WORK/aln/07_reads/` and are reused when the same assembly is compared again with the same reads (set `FORCE=1` to redo them). Output, in `results/07_compare/<A>_vs_<B>/`:

- `disagreements.tsv`: one line for each difference, with its type, position in each assembly, size, the number of reads that agree with A, with B and with neither, the decision and the windows that were examined;
- `summary.json`: the numbers by type, decided for A, decided for B, undecided, with proportions and 95 percent intervals;
- `alignment_stats.json`: how much of A lies in the alignment to B.

### Step 1: aligning A to B

minimap2 aligns A (the query) to B (the target) with the preset `asm10`, which allows about 1 percent divergence between the two sequences. Both assemblies come from the same reads, so the aligned parts differ only by consensus errors, which are small after polishing; the preset `asm5` (about 0.1 percent) would cut the alignment at the many small differences of an assembly that is not yet polished, and `asm20` (about 5 percent) would start to align the copies of similar gene pairs to each other. The choice can be changed with the variable `PRESET`. The option `--secondary=no` keeps for each part of A only its best place in B.

### Step 2: what counts as a difference

Terms. A piece is a stretch of one contig of A that aligns to one contig of B in one orientation. Pieces are made by cutting the alignment at every insertion or deletion of at least 1,000 bases (`MIN_SV`) and keeping pieces of at least 5,000 bases (`MIN_PIECE`); a piece that is covered for more than half of its length by longer pieces on the same contig is dropped because it is a second copy of the same region and not a different arrangement. A junction is the place where two pieces follow each other along a contig. Junctions are read along the contigs of A and along the contigs of B (so that a place where A is continuous and B is broken, and the reverse, are both found); a junction that is found in both views is listed once.

Types, for a junction in the focus assembly F (A or B) with the other assembly O:

| Type | Definition |
|---|---|
| insertion_in_F | both pieces lie on the same contig of O in the same orientation and F holds at least 1,000 bases more between them than O does (F carries a segment that O lacks) |
| deletion_in_F | the same, with O holding at least 1,000 bases more (F lacks a segment) |
| duplication_in_F | the second piece starts in O behind the end of the first by more than 1,000 bases but by no more than the length of the shorter piece: F repeats a segment that O holds once |
| inversion_in_F | three pieces on one contig of O; the middle one has the opposite orientation, and its far end lies within 20,000 bases of the end of the first piece (`MAX_LOCAL`) |
| inversion_breakpoint_in_F | one change of orientation of that kind that is not closed by a third piece (for example at a contig end) |
| relocation_in_F | both pieces on the same contig of O but the second is not where the first leads to (different order, far away, or a change of orientation that is not local) |
| join_in_F | the pieces lie on different contigs of O and each ends within 10,000 bases of the contig end of O that it points to: F is continuous where O is broken. Seen from the other assembly this is a break |
| translocation_in_F | the pieces lie on different contigs of O that both continue beyond the junction |

A break in A is therefore a join in B, and the table lists it as `join_in_B`. Size is the length of the insertion or deletion, of the duplicated segment or of the inverted segment, in bases.

What is not detected: differences below 1,000 bases (the Illumina-based base accuracy of step 08 covers small differences), inversions with an inverted piece shorter than 5,000 bases, regions of A that do not align to B at all (reported as the bases of A that lie in pieces in `alignment_stats.json`), and differences inside repeats that minimap2 places with low confidence.

### Step 3: the reads decide

The PacBio reads are aligned to A and to B separately (minimap2, preset `map-pb`, the preset for PacBio reads with their high error rate). Each of the two arrangements of a difference is tested in the alignment of the reads to the assembly that holds it.

1. For each arrangement the junction points on its assembly are taken and widened by 500 bases to each side (`FLANK`); points closer than 1,000 bases to each other form one window. Windows that would reach beyond the contig end are dropped.
2. A read supports an arrangement if one alignment record of the read, with mapping quality of at least 10, covers a whole window and has no insertion or deletion of 200 bases or more inside it. This means that the read carries the junction together with 500 bases of sequence on both sides. A read is counted once for each arrangement.
3. A read that crosses a window of both arrangements (for example inside a duplicated sequence, which both assemblies contain) does not discriminate and is counted as supporting neither.
4. For a join, the assembly that is broken has no window that a read could cross. For the arrangement of the broken assembly the reads counted are those that are aligned up to the junction of the continuous assembly (within 300 bases, with at least 500 bases aligned beside it) and carry at least 500 further bases that do not continue there. Such reads leave the junction in a direction that the join does not allow.
5. The count of reads for neither arrangement is the number of reads that overlap a window or junction by at least 100 bases but support neither.

Decision. A difference is decided for A if at least 3 reads support A and the number of reads that support A is at least twice the number that support B (and the same with A and B exchanged). Examples, as reads for A / reads for B: 8 / 3 is decided for A (8 is more than twice 3); 4 / 0 is decided for A; 5 / 4 is mixed (both have at least 3 reads but neither has twice the other); 2 / 0 is insufficient (fewer than 3 reads). It is called mixed if at least 3 reads support A or B in total but neither reaches that criterion, for example where the two arrangements both occur in the reads because a repeat is collapsed or the genome is heterozygous. It is called insufficient if fewer than 3 reads support either arrangement. Mixed and insufficient are both undecided. The rule is fixed here and uses no information from the assemblies themselves.

Why a long insertion is decided with fewer reads than one would fear: a segment longer than the reads cannot be crossed by one read in the arrangement that contains it, but the windows lie at each end of the segment, so a read that enters the segment from either side is sufficient. In the arrangement without the segment a single window suffices, and any read that crosses it supports that arrangement.

### Summary numbers

`summary.json` gives the number of differences ({{results/07_compare/proc_r3_vs_hw2/summary.json:disagreements}} for the pair proc_r3 and hw2), the number by type, and the number decided for A, decided for B and undecided. The proportion of all differences decided for A and for B, and the proportion undecided, are each given with a 95 percent confidence interval of the Wilson type (the score interval for a proportion, which keeps its limits between 0 and 1 and behaves well for small numbers; the sample size is the number of differences). One more figure, the proportion of the decided differences that were decided for A, is given with the same interval and with the number of decided differences as the sample size. Because junctions that lie close together are not independent of each other, the intervals are a guide to the counting uncertainty and do not include this dependence.

The summary of the pair A = proc_r3 and B = hw2 shows {{results/07_compare/proc_r3_vs_hw2/summary.json:decided_for_A.proportion}} of the differences decided for A, {{results/07_compare/proc_r3_vs_hw2/summary.json:decided_for_B.proportion}} decided for B and {{results/07_compare/proc_r3_vs_hw2/summary.json:undecided.proportion}} undecided.

### Check on a case with a known answer

`scripts/07_synthetic_check.py` builds two assemblies of a synthetic genome with eleven planted differences (deletions, insertions of 1,500 to 30,000 bases, a tandem duplication, inversions, a break and a join) and reads drawn from the true genome with 12 percent errors, and checks that the decision for every planted difference is the true one and that no other difference is listed:

```bash
python scripts/07_synthetic_check.py make $WORK/synthetic_07
sbatch --export=ALL,A_ASM=synA,B_ASM=synB,FASTA_A=$WORK/synthetic_07/A.fa,FASTA_B=$WORK/synthetic_07/B.fa,READS=$WORK/synthetic_07/reads.fastq,READS_TAG=synthetic,OUT=$WORK/synthetic_07/out jobs/07_compare_adjudicate.sbatch
python scripts/07_synthetic_check.py check $WORK/synthetic_07/out/disagreements.tsv
```

The last command prints one line for every planted difference and ends with status 0 when all are decided correctly. This check shows that the rules above do what they say; it does not show how they behave in the real, repetitive genome, where many differences sit in repeats and will be undecided.

### Resources

The job requests 16 cores, 32 GB of memory and 4 hours (the trial on 12 percent of the reads needed about one minute); the alignment of the reads to the two assemblies dominates. Cached read alignments make the second comparison that involves the same assembly much shorter.
