## Step 06: evaluations 1 to 4 for each assembly

### What the step does

One job per assembly carries out four of the five evaluations with the same programs, settings and thresholds for every assembly: contiguity (evaluation 1), gene-space completeness (evaluation 2), structural correctness against the PacBio reads (evaluation 3) and redundancy and collapse (evaluation 4). Evaluation 5, base accuracy from the Illumina reads, belongs to another step; the comparison of two assemblies with each other, the transcripts assembled without a genome and the mitochondrial genome also belong to other steps. The job writes one table per measure and a file `summary.json` with fixed key names, so that the later steps (the noise scale, the decision table, the figures) read numbers from files and never retype them.

The job is `jobs/06_tests.sbatch`. It takes the assembly name (`ASM`) and the FASTA file (`FASTA`) and nothing else is needed. It uses 16 cores and a few gigabytes of memory, and the steps are independent of each other, so an interrupted job can be submitted again: finished steps are skipped (a marker file per step is kept with the large files) unless `FORCE=1` is set.

### Reference data (fetched once, used offline)

Two reference sets are needed and are stored outside the folder; the script `scripts/06_fetch_databases.sh` (run through the job `jobs/02_fetch_databases.sbatch`) fetches them and writes their source, version and checksum to `envs/databases.tsv`:

1. The lineage `fungi_odb10` of BUSCO (Benchmarking Universal Single-Copy Orthologs): 758 genes that are expected once in the genome of almost every fungus.
2. The reviewed entries of UniProt (Swiss-Prot) for the taxonomy Fungi, taken through the UniProt REST (representational state transfer) interface. Reviewed means that the protein sequence was checked by a curator; the proteins come from many fungi, mostly not close relatives of *Hortaea werneckii*.

```bash
sbatch jobs/02_fetch_databases.sbatch   # or: bash scripts/06_fetch_databases.sh on a node with internet access
bash scripts/06_versions.sh        # writes envs/versions_06.tsv from what the programs report
```

### Command

```bash
cd "$HW"                                              # the package folder; the job is submitted from here
sbatch --export=ALL,ASM=hw2 jobs/06_tests.sbatch      # FASTA defaults to $WORK/asm/hw2/final.fasta
# the same without a scheduler:
ASM=hw2 bash jobs/06_tests.sbatch
```

Further parameters, all optional: `PB_READS` (PacBio reads for the read-back, default the high-quality reads after the contaminant screen), `RNA_DIR` and `RNA_RUN` (RNA-seq FASTQ files, default the HiSeq run), `RES_OUT` and `BIG_OUT` (where tables and large files go), `STAR_BAM=1` (keep the RNA alignments as a sorted BAM file, about 16 GB per assembly), `FORCE=1`. The job stops at once if the reads or the databases are missing.

Tables go to `results/06_tests/<ASM>/`; large files (read alignments, the self-alignment, the protein alignments, the RNA alignment) go to the work folder `$WORK/tests/<ASM>/`.

### The measures, and why each is made this way

<details><summary>Evaluation 1: contiguity</summary>

File `contiguity.tsv` and `contiguity.json`. Contigs are sorted from the longest. **N50** is the length of the contig at which the running sum of lengths first reaches half of the total length, and **L50** is the number of contigs needed to get there. **NG50** and **LG50** are the same with half of the genome size (50 Mb) in place of half of the assembly length, so assemblies of different total length are comparable; they are 0 when the assembly is shorter than half of the genome size. **auN** is the sum of the squared contig lengths divided by the sum of the contig lengths. It answers the question: if one base of the assembly is picked at random, how long is the contig that contains it, on average? A contig of length L contains a fraction L/total of all bases, so it is picked with probability L/total, and the average of the lengths of the picked contigs is the sum of L x (L/total) over all contigs, which is the formula above. Example: an assembly of two contigs of 90 kb and 10 kb has auN = (90 x 90 + 10 x 10) / 100 = 82 kb, because nine bases in ten lie in the 90 kb contig, while the mean contig length is 50 kb. Unlike N50, auN changes smoothly when any contig changes length, so it summarises the whole length distribution in one number. GC content is the percentage of G and C among the unambiguous bases. Two rows are given, all contigs and contigs of at least 10 kb. A wrong join raises N50 as well, so this line is never read alone.

</details>

<details><summary>Evaluation 2: gene-space completeness (BUSCO, RNA-seq, proteins)</summary>

1. **BUSCO** (`busco*.tsv`, `busco_full_table.tsv`). BUSCO is run in genome mode: it finds the genes of the lineage in the assembly with miniprot and classifies each as complete (found once: single; found more than once: duplicated), fragmented or missing. The counts are taken from the full table and checked against the one-line summary of BUSCO. In a genome with a real second set of similar copies, a high duplicated count is expected and is not an error by itself; it is read together with evaluation 4 (redundancy and collapse).
2. **RNA-seq read pairs** (`star*.tsv`). All read pairs of the HiSeq run (SRR5086622, 175 million pairs) are aligned with STAR (Spliced Transcripts Alignment to a Reference). The MiSeq run of the same condition (SRR5086621, 3.3 million pairs, 2 percent of the HiSeq run) is used for quality control only, because it would add little to the alignment test. An intron is a stretch of the genome that is cut out of the RNA, so a read pair from RNA can align in two parts. The longest intron and the longest gap between the two mates are limited to 5,000 bases, which is long for a fungal intron, so that the limit does not decide the result; up to 20 places are allowed per read. The fractions of pairs aligned to one place, to several places, to more than 20 places and not aligned add up to 1. The splice junctions found are also counted, with the fraction that carry the usual splice signal (GT/AG, GC/AG or AT/AC at the intron ends); a high fraction means that the introns found are real. Only counts are kept by default, because the alignment file is large and no step of the workflow reads it.
3. **Swiss-Prot fungal proteins** (`miniprot*.tsv.gz`, `miniprot.json`). Each protein is aligned to the assembly with miniprot, which aligns a protein to DNA across introns and reports frameshifts (a base inserted or missing, which shifts the reading frame) and in-frame stop codons. A protein is *found whole* if its best alignment covers at least 90 % of its length, and *intact* if it is whole and has no frameshift and no in-frame stop. Frameshifts and premature stops per megabase of coding sequence give a second view of base accuracy inside genes. Many proteins of the set are homologues of one gene, so counting every alignment would count the same place many times: whole alignments are sorted by score and one is kept only if less than half of it lies on a place already kept. The denominator is the coding sequence of the kept alignments. A frameshift can also be placed by miniprot to explain a difference between species, which happens for distant proteins; for this reason the same counts are given for the kept alignments with an amino-acid identity of at least 0.7 (keys ending in `_high_identity`). The counts are comparable between assemblies, not absolute error rates.

</details>

<details><summary>Evaluation 3: structural correctness (read-back, junctions, telomeres)</summary>

**Read-back** (`readback*.tsv`, `readback.json`). All PacBio reads that passed the contaminant screen (the raw high-quality subreads of step 02, not the corrected reads used for the assembly) are aligned to the assembly with minimap2 (preset `map-pb`, secondary alignments off), so each read has one primary alignment and, when it aligns in several pieces, supplementary alignments for the other pieces. The definitions are:

- *aligned over at least 80 %*: the aligned parts of all alignments of the read, merged, cover at least 80 % of the read. The same with the primary alignment alone is given as *one piece over at least 80 %*.
- *identity*: 1 minus the edit distance divided by the alignment columns (matches, mismatches, insertions and deletions) of the primary alignment; the median over reads. Raw PacBio reads of this chemistry have an error of about 15 %, so the median is expected to be near 85 %, not near 100 %.
- *in pieces*: two or more alignments of at least 500 read bases each, as a fraction of the reads that align.
- *junction*: a position of a contig at least 1,000 bases from both contig ends; it is the place where two pieces of the assembly could have been joined wrongly. A junction is *spanned* when one alignment of one read crosses it with at least 1,000 aligned bases on each side. The positions that no read spans form gaps of support (`readback_unspanned_gaps.tsv`; one row per gap, 0-based start and end) and are counted per contig (`readback_per_contig.tsv`). Contigs shorter than 2,001 bases cannot be tested and are counted separately. Positions near a contig end are left out because a read cannot cross a contig end by construction; the spanning requirement on both sides is what makes the test about joins.
- *discordant junction*: two neighbouring pieces of one read that do not follow each other on the assembly (different contig or strand, or a distance on the assembly below -1,000 or above 20,000 bases). The break points are the ends of the two pieces that face each other. Break points within 500 bases of a contig end are *at contig ends* (a read runs from the end of one contig into another one: a possible missing join); the others are *interior* (a possible wrong join, or a repeat that the reads cannot place). Break points of the same contig within 300 bases of each other are merged and clusters supported by at least 3 different reads are listed in `readback_discordant_junctions.tsv`. A read-supported interior cluster is a place to look at, not proof of an error; the step that compares two assemblies uses the reads as the referee.

**Telomeres** (`telomeres.tsv`, `telomeres.json`; descriptive). An end of a contig carries a telomere repeat if the first or the last 400 bases contain at least 6 uninterrupted copies of TTAGGG, on either strand. Contigs are counted with repeats at both ends, at one end or at none. Contigs shorter than 800 bases have overlapping windows and are counted in a separate key.

</details>

<details><summary>Evaluation 4: redundancy and collapse (depth, self-alignment)</summary>

1. **Depth** (`depth*.tsv`, `depth_1kb_windows.bed.gz`). mosdepth computes the depth of the PacBio reads in windows of 1 kb (the last window of a contig is shorter). The median is weighted by window length. The fraction of bases in windows from 0.5 to 1.5 times the median is the measure used: two copies merged into one contig give about twice the median, a region present twice by error gives about half. The windows at the two ends of each contig are left out in a second value (`_inner`), because depth falls at a contig end by construction. The fractions in the classes below 0.25, 0.25 to 0.5, 1.5 to 2.5 and at least 2.5 times the median are also written; the mitochondrial genome falls in the last class because it is present in many copies per cell.
2. **DNA-level redundancy** (`redundancy*.tsv`, `redundancy.json`). minimap2 (preset `asm20`, which accepts up to about 20 % difference, with base-level alignment) aligns the contigs against each other; a contig is not aligned to itself, so repeats inside one contig are not examined. For each base of each contig the *best partner* is the alignment block (at least 1,000 columns) with the highest nucleotide identity (matches divided by alignment columns) among the blocks that cover the base, whether the contig is the query or the target of the block. By definition, bases with a best partner at 98 % identity or more are *false duplication* (a region present twice by error), and bases with a best partner from 80 % to below 95 % are *real similar copies* of this genome, not errors. Bases from 95 % to below 98 % belong to neither class and are written separately. A contig is *redundant* if at least 90 % of its bases have a partner at 98 % or more. This is DNA-level identity; it is not the identity of translated proteins. Because the best partner is chosen among alignments of 80 % identity and higher, the 80 % limit is also the limit of what the aligner can find: regions more different than that are counted as having no partner.

</details>

### Expected output

- `results/06_tests/<ASM>/summary.json` and `summary.tsv` (the same numbers, one key per row). Key names are given below.
- For the published assembly Hw 2.0 (651 contigs) the contiguity values are those published with it; compare {{results/06_tests/hw2/summary.json:contiguity.all.contigs}}, {{results/06_tests/hw2/summary.json:contiguity.all.total_bp}} and {{results/06_tests/hw2/summary.json:contiguity.all.n50}} (contigs, total bases and N50) with them.
- `summary.json` has an empty list under `steps_failed`; if a step failed, its key holds `null` and the name of the step is listed.
- The number of reads in `inputs.pacbio_reads` must be that of the read set of step 02 (718,442 high-quality reads before the contaminant screen), and `inputs.rna_pairs` that of the HiSeq run (175,019,208 read pairs). Smaller numbers mean that a sub-sample was used and every value is provisional.
- `timings.tsv`: wall time and peak memory of every program in the job.

<details><summary>Keys of summary.json</summary>

All keys are fixed; a value that could not be computed is `null`. Fractions are between 0 and 1 unless the name says percent.

| Key | Meaning |
|---|---|
| `assembly` | name of the assembly |
| `inputs.pacbio_reads_file`, `inputs.pacbio_reads` | PacBio read file used for the read-back and the number of reads in it |
| `inputs.rna_run`, `inputs.rna_pairs` | RNA-seq run aligned and the number of read pairs |
| `contiguity.all.*`, `contiguity.ge10kb.*` | for all contigs and for contigs of at least 10 kb: `contigs`, `total_bp`, `n50`, `l50`, `ng50`, `lg50`, `aun`, `longest`, `gc_percent`, `ambiguous_bases` |
| `contiguity.genome_size_used_for_ng50` | genome size of the plan (50,000,000) |
| `busco.busco_genes`, `busco.complete`, `busco.complete_single`, `busco.complete_duplicated`, `busco.fragmented`, `busco.missing` | counts of BUSCO genes (lineage `fungi_odb10`) |
| `busco.complete_percent`, `busco.single_percent`, `busco.duplicated_percent`, `busco.fragmented_percent`, `busco.missing_percent` | the same as percent of the genes |
| `star.input_pairs`, `star.unique_pairs`, `star.multiple_pairs`, `star.too_many_pairs`, `star.unmapped_pairs` | RNA read pairs by class |
| `star.frac_unique`, `star.frac_multiple`, `star.frac_too_many`, `star.frac_unmapped` | the same as fractions of the input pairs |
| `star.mismatch_rate_percent`, `star.deletion_rate_percent`, `star.insertion_rate_percent` | rates per aligned base, as reported by STAR |
| `star.average_input_read_length`, `star.average_mapped_length` | read length of the input and of the aligned part |
| `star.splice_junctions_detected`, `star.junction_reads_canonical`, `star.junction_reads_noncanonical`, `star.frac_junction_reads_canonical` | junctions found and reads across them by splice signal |
| `miniprot.proteins_total`, `miniprot.proteins_aligned`, `miniprot.proteins_whole`, `miniprot.proteins_intact` | proteins of the set, aligned, found whole (coverage of at least `min_coverage_for_whole`) and intact |
| `miniprot.frac_proteins_whole`, `miniprot.frac_proteins_intact`, `miniprot.median_identity_whole` | fractions of all proteins; median amino-acid identity of the whole alignments |
| `miniprot.loci_kept`, `miniprot.coding_bases_kept` | places left after removal of repeated loci and their coding sequence |
| `miniprot.frameshifts_in_kept`, `miniprot.stop_codons_in_kept` | counts over the kept alignments |
| `miniprot.frameshifts_per_mb_coding`, `miniprot.stop_codons_per_mb_coding` | per megabase of kept coding sequence |
| `miniprot.frameshifts_per_mb_assembly`, `miniprot.stop_codons_per_mb_assembly` | per megabase of assembly |
| `miniprot.loci_kept_high_identity`, `miniprot.coding_bases_kept_high_identity`, `miniprot.frameshifts_high_identity`, `miniprot.stop_codons_high_identity`, `miniprot.frameshifts_per_mb_coding_high_identity`, `miniprot.stop_codons_per_mb_coding_high_identity` | the same for kept alignments with amino-acid identity of at least `min_identity_for_high` |
| `miniprot.min_coverage_for_whole`, `miniprot.min_identity_for_high` | the thresholds used (0.9 and 0.7) |
| `readback.reads_total`, `readback.reads_unmapped`, `readback.reads_with_alignment` | reads, reads without alignment, reads with a primary alignment |
| `readback.frac_reads_aligned_ge80pct`, `readback.frac_reads_one_piece_ge80pct` | fraction of all reads aligned over at least 80 % of their length (all pieces merged; primary alignment alone) |
| `readback.median_identity` | median identity of the primary alignments |
| `readback.reads_in_pieces`, `readback.frac_reads_in_pieces` | reads aligned in two or more pieces, and their fraction of the reads with an alignment |
| `readback.discordant_junction_pairs` | pairs of neighbouring pieces of a read that are not collinear on the assembly |
| `readback.discordant_junction_clusters_interior_ge_min_reads`, `readback.discordant_junction_clusters_at_contig_ends_ge_min_reads` | clusters of break points supported by at least `parameters.min_reads` reads, away from and at contig ends |
| `readback.junction_test_contigs_too_short`, `readback.junction_tested_bases` | contigs that cannot be tested, and the bases of the contigs that are tested (without the 1,000 bases at each end) |
| `readback.unspanned_bases`, `readback.unspanned_gaps`, `readback.frac_tested_bases_unspanned` | tested positions that no read spans, the number of gaps they form, and their fraction |
| `readback.parameters.*` | thresholds used: `flank`, `min_piece`, `end_margin`, `cluster_window`, `min_reads` |
| `depth.median_depth`, `depth.mean_depth`, `depth.windows`, `depth.bases`, `depth.windows_terminal` | median (weighted by window length) and mean depth, windows, bases, windows at contig ends |
| `depth.frac_below_0_25`, `depth.frac_0_25_to_0_5`, `depth.frac_0_5_to_1_5`, `depth.frac_1_5_to_2_5`, `depth.frac_at_least_2_5` | fraction of the bases in windows by depth relative to the median; `frac_0_5_to_1_5` is the measure of the plan |
| `depth.frac_0_5_to_1_5_inner` | the same without the windows at contig ends |
| `redundancy.assembly_bases` | bases of the assembly |
| `redundancy.false_duplication_bases_ge98`, `redundancy.false_duplication_fraction` | bases whose best partner has 98 % identity or more, and their fraction |
| `redundancy.between_95_98_bases` | bases whose best partner has 95 % to below 98 % identity |
| `redundancy.real_similar_bases_80_to_95`, `redundancy.real_similar_fraction` | bases whose best partner has 80 % to below 95 % identity, and their fraction |
| `redundancy.no_partner_bases` | bases without a partner of 80 % or more |
| `redundancy.redundant_contigs_ge90pct` | contigs with at least 90 % of their bases in false duplication |
| `redundancy.paf_records`, `redundancy.paf_records_used`, `redundancy.min_block` | alignment records read, records used (between different contigs and at least `min_block` columns), the minimum block (1,000) |
| `telomeres.contigs`, `telomeres.with_repeat_at_both_ends`, `telomeres.with_repeat_at_one_end`, `telomeres.with_no_repeat` | contigs by number of ends with a telomere repeat |
| `telomeres.contigs_shorter_than_two_windows`, `telomeres.window_bases`, `telomeres.min_repeats` | contigs shorter than 800 bases, window (400) and repeat number (6) |
| `steps_failed` | names of the steps that did not finish (empty list when all finished) |

</details>

### Limits

- The alignment of contigs against each other does not look at repeats inside one contig and cannot see similar regions below about 80 % identity; the classes used here (98 % and above, 80 % to 95 %) lie inside what it can find.
- Raw-read depth and the read-back depend on the read set; for every assembly the same reads are used, so differences between assemblies come from the assemblies.
- The count of frameshifts and stops in proteins depends on how close the proteins are to *H. werneckii*; it is used to compare assemblies, not as an absolute error rate.
- The thresholds (80 % of the read length, 1,000 bases of flank, 3 reads for a cluster, 98 % and 80 to 95 % identity) were fixed before the results were seen and are the same for every assembly.
