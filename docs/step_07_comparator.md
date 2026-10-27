# Step 07: the comparator Hw 2.0, its 22 unexplained sequences and the mitochondrial genome

Summary. Hw 2.0 (the published assembly of strain EXF-2000) is the comparator of the whole package, so before it is used we establish exactly what the files that carry it contain (part 7a), what the 22 sequences are that the NCBI (National Center for Biotechnology Information) record leaves out (part 7b), and which contig is the mitochondrial genome, in Hw 2.0 and in every other assembly (part 7c). The three parts have separate scripts and separate result folders under `results/07_comparator/`. Every number quoted below is written to a file by a script; the placeholders in double braces name the file and the key.

## 7a. The files that carry Hw 2.0

### Idea

Several files claim to hold Hw 2.0: the complete file of the GitHub repository (`Hw2.fasta.gz`), the genome files that were prepared for submission to GenBank (`Hw2.MTedit.fasta` and the files `genome.fasta` of the folders `annotated1` and `fixed1`), and the record GCA_002127715.1 at NCBI. The package uses the first one in every test, so it must be known whether the others are the same sequence. The comparison is done contig by contig: contig names and lengths, then a checksum of the sequence of each contig (MD5, a 128-bit fingerprint that changes if a single base changes). Where two sequences of the same contig differ, they are aligned (minimap2, preset `asm5`, which accepts up to 5 % divergence) and the substitutions and insertions or deletions are counted. Letter case is compared separately, because soft-masked (lower-case) bases do not change the sequence.

### What was found

- The GitHub file holds {{results/07_comparator/genbank_files/summary.json:github_contigs}} contigs and {{results/07_comparator/genbank_files/summary.json:github_bases}} bases.
- The NCBI record holds {{results/07_comparator/genbank_files/summary.json:ncbi_contigs}} contigs. Its contig names are accessions; the assembly report of the record maps each to the name of the GitHub file. After the mapping, {{results/07_comparator/genbank_files/summary.json:ncbi_contigs_with_identical_sequence_in_github}} of them have a sequence identical to the GitHub contig when letter case is ignored. In the GitHub file the repeats are written in lower case (soft-masked) and in the NCBI record every base is upper case; this is the only difference (`case_differences.tsv`).
- `annotated1/genome.fasta` and `fixed1/genome.fasta` carry the same contigs as the GitHub file, base for base, including letter case (`file_summary.tsv`, column `identical_sequence`).
- `Hw2.MTedit.fasta` carries the same sequences; one contig has another name: the mitochondrial contig `unitig_320` is called `MT`. The sequence of `MT` is identical to the sequence of `unitig_320` (`only_in_one_file.tsv`). The list of sequences that differ (`differing_sequences.tsv`) is therefore empty: no substitution, no insertion or deletion, nothing mitochondrial that differs. The annotation file `MT_genome.gff3` of the repository uses the name `MT`.
- The file `annotation/GenBank/Hw2.fasta` named in the repository is a soft link to `assemblies/Hw2/Hw2.fasta`, which is not in the repository (the repository stores only the compressed file). The link is broken and nothing could be compared; the status is recorded in `file_summary.tsv`.
- The NCBI record places `unitig_320` ({{results/07_comparator/genbank_files/summary.json:ncbi_mito_length}} bases, accession {{results/07_comparator/genbank_files/summary.json:ncbi_mito_accession}}) in a separate non-nuclear unit as the mitochondrion.
- {{results/07_comparator/genbank_files/summary.json:absent_from_ncbi}} sequences of the GitHub file are absent from the NCBI record; they are present in the other genome files of the repository (part 7b examines them).

In plain terms: all the GenBank files of the repository contain the complete GitHub file, only renamed in one contig; the NCBI record contains the same sequence for all of its contigs, but not for the 22 short ones. The package therefore loses nothing by using the GitHub file, and it knows what the NCBI record leaves out.

### Command

```bash
cd "$HW" && sbatch jobs/07_genbank_files.sbatch      # about 1 minute, 8 GB, 2 cores
```

Output in `results/07_comparator/genbank_files/`: `file_summary.tsv` (one row per file), `contigs_by_file.tsv` (length and checksum of every contig in every file), `differing_sequences.tsv`, `only_in_one_file.tsv`, `case_differences.tsv`, `the22_ids.tsv` (the 22 sequences: name, length, GC content, checksum) and `summary.json`.

## 7b. The 22 sequences

### Idea

Neither the paper nor the NCBI record says why 22 short sequences ({{results/07_comparator/the22/summary.json:min_length}} to {{results/07_comparator/the22/summary.json:max_length}} bases, {{results/07_comparator/the22/summary.json:total_bases}} bases in all) were left out. They are not removed from the statistics in advance. Each is examined from five sides, so that its nature can be named from evidence:

1. **Redundancy.** The sequence is aligned (minimap2, preset `asm20`, up to about 20 % divergence, all alignments kept) to every other contig of Hw 2.0; for each sequence the fraction covered by an alignment, the same at 98 % identity or more (the threshold of the false-duplication criterion), the best partner contig and its identity are reported. A sequence covered over its whole length at 98 % or more is a second copy of sequence that Hw 2.0 already holds.
2. **Mitochondrial origin.** The sequence is aligned to the NCBI mitochondrion record, and its genes are searched with the mitochondrial proteins of related fungi (see 7c).
3. **Gene content.** Reviewed fungal proteins of Swiss-Prot are aligned with miniprot (a protein-to-genome aligner that models introns); a protein counts when at least half of it is covered at 35 % amino-acid identity or more. Three ribosomal DNA records of *Hortaea werneckii* (18S, internal transcribed spacers, 28S; accessions in `envs/databases.tsv`) are aligned with BLAST (blastn) to show whether the sequence is ribosomal DNA, and the beta-lactamase protein TEM-1 of *Escherichia coli* (the ampicillin-resistance gene carried by many cloning vectors) is aligned with tblastn as a marker of vector sequence.
4. **Composition.** GC content (the proportion of G and C bases) of each sequence is given beside the GC content of the nuclear genome ({{results/07_comparator/the22/summary.json:nuclear_gc_length_weighted}}).
5. **PacBio read depth.** All high-quality subreads are aligned to Hw 2.0 with minimap2 (preset `map-pb`); the mean depth over each sequence is divided by the median depth of 1-kb windows of the contigs that are not among the 22 and not mitochondrial. Two ratios are given: all primary alignments, and reads of mapping quality 20 or more only. A sequence that is a near-identical copy of another one receives few reads of high mapping quality, because the aligner cannot tell the two copies apart and assigns each read to one of them; the two ratios together show this, and a sequence of true high copy number has a high ratio in both.

The last columns give the contaminant screen of the 22 sequences (step 02b, the criterion of the screen of reads applied to contigs): the proportion of each sequence aligned to each contaminant group and its class.

### What was found

The table is `results/07_comparator/the22/the22_table.tsv`; the key numbers are in `summary.json` of the same folder:

- Sequences covered over at least 90 % of their length by other contigs of Hw 2.0: {{results/07_comparator/the22/summary.json:other_contigs_coverage_ge_0_9}}; of these at 98 % identity or more: {{results/07_comparator/the22/summary.json:other_contigs_coverage_ge_0_9_at_identity_ge_0_98}}.
- Sequences with an alignment to the mitochondrion record over at least half of their length: {{results/07_comparator/the22/summary.json:with_mito_alignment_ge_0_5}}; with at least one core mitochondrial gene family: {{results/07_comparator/the22/summary.json:with_mito_core_family}}.
- Sequences with a ribosomal DNA alignment: {{results/07_comparator/the22/summary.json:with_rdna_alignment}}; with at least one Swiss-Prot protein: {{results/07_comparator/the22/summary.json:with_swissprot_protein}}.
- Ratio of the depth to the nuclear median: from {{results/07_comparator/the22/summary.json:depth_ratio_min}} to {{results/07_comparator/the22/summary.json:depth_ratio_max}} (all primary alignments).

Reading of the table, from the evidence tags of the table (`evidence_tags`; the thresholds are in the header of `scripts/07_the22.py`):

- {{results/07_comparator/the22/summary.json:other_contigs_coverage_ge_0_9_at_identity_ge_0_98}} of the 22 sequences are second copies: at least 90 % of the sequence is covered by other contigs of Hw 2.0 at 98 % identity or more. They are redundant in the sense of evaluation 4: Hw 2.0 holds the same sequence elsewhere. The best partner, its coverage and its identity are listed per sequence; several sequences have the same partner contig.
- {{results/07_comparator/the22/summary.json:with_rdna_alignment}} sequences align to the ribosomal DNA records and also carry Swiss-Prot protein hits of a ribosomal-DNA neighbourhood (the table names the protein); they are pieces of the ribosomal DNA repeat, a region that assemblers resolve badly because the copies are nearly identical.
- {{results/07_comparator/the22/summary.json:with_vector_marker_bla}} sequence (unitig_426, {{results/07_comparator/the22/the22_table.tsv:unitig_426 length|int}} bases) contains the whole beta-lactamase gene of cloning vectors (column `bla_marker_protein_coverage`) and has no partner among the other contigs. Its depth with all high-quality subreads is {{results/07_comparator/the22/depth_unscreened_and_screened_reads.tsv:unitig_426 mean_depth_unscreened_reads|int}} times, against a nuclear median window depth of {{results/07_comparator/the22/summary.json:nuclear_median_window_depth}} times: it is the sequence of a cloning vector, not of the genome. After the contaminant screen of the reads, which removes the reads that match the vector database, its depth falls to {{results/07_comparator/the22/depth_unscreened_and_screened_reads.tsv:unitig_426 mean_depth_screened_reads|int}} times (a part of the vector reads is kept by the rule of the screen, which excludes a read only when it is mostly contaminant and has no fungal match).
- None of the 22 sequences is mitochondrial: {{results/07_comparator/the22/summary.json:with_mito_alignment_ge_0_5}} align to the mitochondrion record and {{results/07_comparator/the22/summary.json:with_mito_core_family}} carry a core mitochondrial gene.
- The depth of the second copies is far below the nuclear median when only reads of mapping quality 20 or more are counted (column `depth_ratio_mapq20_to_nuclear_median`), as expected for sequence that has an almost identical twin.

The depth in the table is computed from the screened set `hq_clean.fastq` (named in `summary.json` as `depth_reads_file`). The side table `depth_unscreened_and_screened_reads.tsv` gives the depth of the 22 sequences with and without the screen (job `jobs/07_depth_unscreened.sbatch`).

### Commands

```bash
cd "$HW" && sbatch jobs/07_the22.sbatch      # the 22 sequences in Hw 2.0 (needs the output of 7a and the read set of step 02)
# the same alignment against any other assembly:
sbatch --export=ALL,ASM=proc_r3 jobs/07_the22_vs_assembly.sbatch
```

The second command aligns the 22 sequences to `$WORK/asm/<ASM>/final.fasta` (or the file named in `FASTA`) and writes, per sequence, the fraction aligned, the fraction aligned at 98 % and 90 % identity, the best contig and its identity (`results/07_comparator/the22/vs_assemblies/the22_vs_<ASM>.tsv`). It answers whether a new assembly contains these sequences, in one piece or divided over several contigs, or does not contain them. Runtime: about 1 to 2 minutes, 16 GB.

## 7c. The mitochondrial genome

### Idea

A mitochondrial genome is recognised by three independent kinds of evidence, which together are stronger than any one:

1. **Protein evidence.** The mitochondrial proteins of related fungi (reference sequences of RefSeq, the curated collection of NCBI) are aligned to the contigs with tblastn, which translates the contigs in all frames. The genetic code is code 4 (the code of mould and protozoan mitochondria, in which the codon TGA codes for tryptophan instead of a stop). With the standard code the genes would be broken at every TGA. A core gene family (`nad1`-`nad6`, `nad4L`, `cox1`-`cox3`, `cob`, `atp6`, `atp8`, `atp9`) counts as found when one reference protein is covered over at least half of its length. A contig with at least 4 of the 14 core families is classified mitochondrial. The references are the mitochondrial genomes of four Dothideomycetes (the class of *Hortaea*), *Zymoseptoria tritici* (NC_010222.1), *Pseudocercospora fijiensis* (NC_044132.1), *Cladosporium sphaerospermum* (NC_050879.1), *Zasmidium cellare* (NC_030334.1) and, as an outgroup, *Saccharomyces cerevisiae* (NC_001224.1); accessions and download date are in `envs/databases.tsv`. Nuclear genes similar to a mitochondrial gene (for instance a nuclear copy of `atp9`) produce one or two hits on nuclear contigs; the threshold of 4 families prevents them from being called mitochondrial.
2. **Genome evidence.** The contigs are aligned to the five reference mitochondrial genomes with minimap2 (preset `asm20`); the number of aligned bases is reported for every contig.
3. **Depth and composition.** The mitochondrial genome is present in many copies per cell, so its read depth is a multiple of the nuclear depth, and its GC content is lower than that of the nucleus. A contig with only part of the evidence (one core family or 1,000 aligned bases) is called a candidate when its depth ratio is 3 or more; without depth data it is listed as a candidate without depth.

The script then reports, for each mitochondrial contig: length, GC content, number of core families, depth and depth ratio, and **circularity**. A circular genome assembled into a linear contig usually has its two ends overlapping, because the assembler read around the circle more than once. The script looks for the beginning of the contig at its end, exactly (at least 30 bases) and by alignment (at least 100 aligned bases at 90 % identity or more), and reports the overlap; the length of the circle is then the contig length minus the overlap. Finally the mitochondrial contigs are aligned to the NCBI mitochondrion record (`unitig_320` of Hw 2.0, accession {{results/07_comparator/genbank_files/summary.json:ncbi_mito_accession}}) and the proportion of each sequence covered, the identity of the alignment and the numbers of substitutions and of inserted and deleted bases are reported. The statistics of the assembly are given with and without the mitochondrial contigs.

### What was found for Hw 2.0

Read from `results/07_comparator/mito/hw2/summary.json`:

- number of mitochondrial contigs (pieces): {{results/07_comparator/mito/hw2/summary.json:mitochondrial_pieces}}, total length {{results/07_comparator/mito/hw2/summary.json:mitochondrial_length}} bases; core families found: {{results/07_comparator/mito/hw2/summary.json:core_families_found_union_count}} of 14;
- the contig {{results/07_comparator/mito/hw2/summary.json:longest_mito_contig}} has {{results/07_comparator/mito/hw2/summary.json:longest_mito_length}} bases and a GC content of {{results/07_comparator/mito/hw2/summary.json:longest_mito_gc}} (nuclear {{results/07_comparator/mito/hw2/summary.json:gc_nuclear_length_weighted}}); its mean depth is {{results/07_comparator/mito/hw2/summary.json:longest_mito_mean_depth}}, which is {{results/07_comparator/mito/hw2/summary.json:longest_mito_depth_ratio}} times the nuclear median ({{results/07_comparator/mito/hw2/summary.json:nuclear_median_window_depth}}); the depth is computed from the file named under `depth_reads_file` (the screened set `hq_clean.fastq`);
- circularity: the two ends overlap over {{results/07_comparator/mito/hw2/summary.json:longest_mito_end_overlap_aligned_bases}} aligned bases (exact identical bases at the very ends: {{results/07_comparator/mito/hw2/summary.json:longest_mito_end_overlap_exact_bases}}), so the sequence is a circle of about {{results/07_comparator/mito/hw2/summary.json:longest_mito_circle_length_estimate}} bases written with a repeated end;
- coverage of the NCBI mitochondrion record: {{results/07_comparator/mito/hw2/summary.json:comparison_with_ncbi_mitochondrion.ncbi_record_coverage}}, identity of the alignment {{results/07_comparator/mito/hw2/summary.json:comparison_with_ncbi_mitochondrion.identity_of_aligned}}.

Because the mitochondrial contig of Hw 2.0 is the sequence of the NCBI record, its comparison with the record is a check that the script finds the record and nothing more: identity and coverage should be 1. The comparison becomes informative for the new assemblies.

### Command (any assembly)

```bash
cd "$HW"
sbatch --export=ALL,ASM=hw2 jobs/07_mito.sbatch          # Hw 2.0: about 40 minutes (the alignment of the reads dominates), 48 GB, 16 cores
sbatch --export=ALL,ASM=proc_r3 jobs/07_mito.sbatch      # any assembly named ASM; FASTA and READS can be given too
```

When the same assembly has been through the read alignment already (`$WORK/07_comparator/<ASM>/reads_vs_asm.bam` and the depth tables), the alignment is reused and the job takes a few minutes. Output in `results/07_comparator/mito/<ASM>/`: `summary.json` (key numbers), `mito_contigs.tsv`, `candidate_contigs.tsv`, `contigs_with_evidence.tsv` (every contig with any evidence or a depth ratio of 5 or more), `tblastn_hits.tsv`, `ref_genome_alignments.paf`, `ncbi_mito_alignments.paf`, `ncbi_mito_vs_assembly.paf`.

The reference set is fetched once by `scripts/07_fetch_mito_refs.sh` (called by the job when `$DBS/mito_refs` is empty); the ribosomal DNA records by `scripts/07_fetch_rdna_refs.sh`.

## What is not done and the limits

- The depth of a sequence is the depth of primary alignments of long, noisy reads. Near-identical copies divide their reads among them, so the depth of a copy is below its true value and the sum over the copies is closer to the truth; this is why two ratios are given in 7b.
- The mitochondrial genes are searched by protein similarity to related fungi. A divergent gene that falls below the coverage threshold would not be counted; the number of families found is a minimum.
- Circularity is judged from the overlap of the ends of a contig. A contig without an overlap may still be a circle (the assembler may have trimmed the overlap), and an overlap does not by itself prove circularity; the reads that span the junction would be the proof and are not examined here.
- The contaminant screen of the 22 sequences uses the screening script of step 02b; the contigs of the other assemblies are screened by `jobs/02_screen_contigs.sbatch`, not by the jobs of this step.
- Programs and versions are in `envs/versions_07.tsv`; databases in `envs/databases.tsv`.

### Glossary

- **GC content**: proportion of G and C bases.
- **MD5**: fingerprint of a text; two sequences with the same MD5 are the same sequence.
- **NCBI**: National Center for Biotechnology Information.
- **RefSeq**: reference sequence collection of NCBI.
- **tblastn**: BLAST (Basic Local Alignment Search Tool) program that compares a protein with a nucleotide sequence translated in all six frames.
- **PacBio**: Pacific Biosciences, the sequencing platform that produced the long reads.
