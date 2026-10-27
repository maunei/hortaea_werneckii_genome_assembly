## Step 02b: screen of the PacBio reads and of contigs for contaminants

### What this step does

Before assembly, every PacBio read is compared with reference sequences of bacteria, archaea, viruses, human and cloning vectors, and with fungal genomes. A read is excluded only if it matches a contaminant over most of its length and has no fungal match. Reads are removed whole; no base of any read is edited or masked. The number of reads and bases excluded is reported for each read set. The same criterion is later applied to the contigs of every assembly (including the published assembly Hw 2.0), so that the contigs flagged as contaminants can be examined without any reference to what Hw 2.0 contains.

The screen uses no sequence of the strain under study: the reference collection holds no *Hortaea* genome, and Hw 2.0 is not used at any point of the read screen.

Outputs (all small tables are in the package; the clean read sets are on the work storage):

| File | Content |
|---|---|
| `results/02_pacbio_reads/screen/counts_by_set.tsv` | per read set (`hq`, `filtered`): number of reads and bases by class and by contaminant group |
| `results/02_pacbio_reads/screen/<set>_excluded_reads.txt` | names of the excluded reads, one per line |
| `results/02_pacbio_reads/screen/<set>_per_read.tsv.gz` | one row per read: fraction of its length covered by fungi and by each contaminant group, closest contaminant reference, class |
| `results/02_pacbio_reads/screen/<set>_by_organism.tsv` | excluded reads, and reads protected by a fungal match, grouped by the closest reference organism |
| `results/02_pacbio_reads/screen/criterion.txt`, `<set>_criterion.json` | the criterion and every parameter as applied |
| `$WORK/reads/pacbio/hq_clean.fastq`, `filtered_clean.fastq` | read sets used by the assemblers (the original files without the excluded reads); the marker `READY_02` is created when both exist |
| `results/02_pacbio_reads/screen_contigs/<ASM>/` | the same tables for the contigs of assembly `<ASM>` |
| `results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv` | result of the self-test with simulated reads of known origin |
| `results/02_pacbio_reads/screen_db/` | sequences and bases per database part, the RefSeq release, and the table linking every database key to its organism |

Results of the run: {{results/02_pacbio_reads/screen/hq_criterion.json:n_excluded|int}} of the `hq` reads and {{results/02_pacbio_reads/screen/filtered_criterion.json:n_excluded|int}} of the `filtered` reads were excluded ({{results/02_pacbio_reads/screen/hq_criterion.json:bases_excluded|int}} of {{results/02_pacbio_reads/screen/hq_criterion.json:bases_screened|int}} bases of `hq`). The clean sets are real files (not links), because reads were excluded.

### The criterion

The rule is: a read is excluded only if it matches a contaminant over most of its length and has no fungal match. The step turns each phrase into a measurement:

1. **Match.** An alignment of the read to a reference sequence counts only if it is at least `MIN_ALN_LEN` = 300 bases long and its identity (residue matches divided by alignment length) is at least 0.70 for contaminant references and at least 0.65 for fungal references. Contaminant matches need stronger evidence because wrongly excluding a read is the costly error; wrongly keeping one is not. Identity here is computed over the alignment including gaps. PacBio reads of this chemistry have about 14 % errors, so a read from a sequence that is in the database aligns at an identity near 0.87, not 1.0.
2. **Most of its length.** The aligned parts of the read on contaminant references (all contaminant groups together; overlapping parts counted once) must cover at least `MIN_CONTAM_FRAC` = 0.5 of the read length.
3. **No fungal match.** No counted alignment of the read to a fungal genome of the database. Any single fungal alignment of 300 bases or more protects the read. This is deliberately conservative: it keeps fungal reads that resemble bacterial or human sequences (ribosomal DNA, mitochondrial DNA, repeats, genes acquired from bacteria).

Every read falls into exactly one class: `excluded`; `contaminant_majority_but_fungal_match_kept`; `contaminant_minor_kept` (some contaminant match but less than half of the read); `fungal_match_only_kept`; `no_match_kept`. Because most reads of a fungus whose close relatives are not sequenced match nothing in the database, `no_match_kept` is the largest class; it means "not recognised as a contaminant", not "recognised as the target species".

The three numbers are set once in `scripts/screen_common.sh` (variables `MIN_ALN_LEN`, `MIN_IDENTITY`, `MIN_IDENTITY_CONTAM`, `MIN_CONTAM_FRAC`) and written to `criterion.txt` with every run. The same values are used for reads and for contigs.

### The tool used (minimap2) and the reference collection

The reads are long (several kilobases) and carry roughly 14 % errors (the figure used for this chemistry in the simulations; real alignments to correct references reach an identity near 0.87), mostly insertions and deletions. The screen therefore uses an aligner that tolerates such errors: minimap2 with the preset `map-pb` (words of 19 bases collapsed in homopolymer runs, chaining of word hits, base-level alignment with the option `-c`). It aligns each read to a reference collection built for this screen and reports the aligned interval of every read, so the fraction of the read that is covered by a contaminant follows directly from the reported intervals, and the screen of all reads runs in minutes. The same program, with the preset `asm20` (accurate sequences, up to 20 % divergence), is used for contigs.

**Reference collection.** It is built by `scripts/fetch_screen_databases.sh` from the public NCBI FTP site (run through the job `jobs/02_fetch_databases.sbatch`). Sequence names are rewritten as `GROUP|KEY|original name`, so that the group of every alignment is read from the name of its target. The database is split in four parts (sizes in `results/02_pacbio_reads/screen_db/parts_stats.tsv`), each with its own minimap2 index (`jobs/02_screen_db_index.sbatch`), because a single index of all parts would need about four times the memory.

| Part | Content | Group names |
|---|---|---|
| `bacteria_1`, `bacteria_2` | one RefSeq genome per bacterial genus (reference genome first, then complete genome, then the longest) | bacteria |
| `fungi` | one RefSeq genome per fungal genus; *Hortaea* excluded (RefSeq holds none) | fungi |
| `other` | one genome per archaeal genus; additional species (rows with `part=extra` in `envs/screen_genomes.tsv`) that are frequent contaminants of sequencing (reagent and laboratory bacteria such as *Pseudomonas*, *Staphylococcus*, *Ralstonia*, *Cutibacterium*; human gut archaea) or live in salt-rich habitats (*Halomonas*, *Halobacterium*); all RefSeq viral genomes (release file `viral.1.1.genomic.fna.gz`); the human genome T2T-CHM13 version 2.0; UniVec (the NCBI collection of vector, adapter and linker sequences) | archaea, bacteria, virus, human, vector |

The number of sequences and bases of each part is in `results/02_pacbio_reads/screen_db/parts_stats.tsv`; the exact list of genomes (accession, organism, assembly level, download address) is `envs/screen_genomes.tsv`, and it is reused when the databases are fetched again, so that a re-fetch gives identical files (checked: the checksums of the parts are in `envs/databases.tsv`). The selection rules are written at the top of `scripts/select_screen_genomes.py`. The RefSeq release used is in `results/02_pacbio_reads/screen_db/refseq_release.txt`. The database lives in `$DBS/screen` on scratch storage, outside the package. Few large files are used on purpose (four sequence files and four indexes), because the storage limits the number of files.

Why one genome per genus and not every genome: all RefSeq bacterial assemblies together hold more than two trillion bases, far beyond what one alignment job can hold. One genome per genus covers every bacterial genus of RefSeq at a size that fits (the two bacterial parts in `parts_stats.tsv`). The consequence is a limit of sensitivity that the self-test measures (next section): a contaminant is recognised if a reference exists within roughly 10 % sequence divergence of it.

### Self-test with reads of known origin

`scripts/screen_selftest.sh` (job `jobs/02_screen_selftest.sbatch`) simulates PacBio-like reads (14 % errors; insertions, deletions and substitutions in the proportion 55:28:17) from known sequences, mixes them with a 2 % random sample of the real `hq` reads, and screens the mixture with the production script. Test genomes that are not in the database (other strains or other species of a genus that is) are fetched by `scripts/fetch_screen_test_genomes.sh`. Diverged copies (substitutions at 5, 10, 15 and 20 %) stand for relatives that are absent from the database, and chimeric reads (3 kb of a bacterial genome joined to 1.5 kb of a diverged fungal genome) test the fungal protection.

The table `results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv` gives, for each kind of control read, the number of reads in each class and the fraction excluded. How to read it:

* Reads from sequences that are in the database (bacterium, archaeon, virus, human) are excluded in nearly all cases ({{results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv:bacteria_in_db_div0 fraction_excluded}} for the bacterial control). The few human reads that are kept carry a fungal match; this is the protective rule at work.
* Sensitivity falls with divergence from the closest reference: {{results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv:bacteria_in_db_div10 fraction_excluded}} at 10 % divergence, {{results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv:bacteria_in_db_div15 fraction_excluded}} at 15 %, {{results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv:bacteria_in_db_div20 fraction_excluded}} at 20 %. Other strains of a species in the database and species of a genus in the database lie in between and depend on the real distance (see the rows for *Escherichia coli* strain CFT073, *Pseudomonas stutzeri* and *Staphylococcus haemolyticus*). The screen therefore detects contaminants that have a close relative in RefSeq; a contaminant with no relative within about 10 % cannot be detected by this procedure, whatever its abundance.
* Fungal control reads are never excluded ({{results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv:fungus_in_db_div0 fraction_excluded}}), and neither are reads of a diverged fungal relative.
* The row `real_reads_sample` shows the classes of the real reads of the sample; the simulation is an approximation of the real error process, so the sensitivity numbers are estimates.

### How to run

Run from the package folder. The databases are fetched once on a computer with internet access, then indexed by a job:

```bash
source config/config.sh
sbatch jobs/02_fetch_databases.sbatch             # BUSCO lineage, Swiss-Prot proteins and this collection; about 30 minutes for the collection (4 parallel downloads)
sbatch jobs/02_screen_db_index.sbatch             # about 10 minutes, 16 cores, 128 GB; makes four .mmi indexes of 8 to 19 GB
bash scripts/fetch_screen_test_genomes.sh         # three small genomes for the self-test (internet needed)
sbatch jobs/02_screen_selftest.sbatch             # about 2 minutes
sbatch jobs/02_screen_reads.sbatch                # production screen of both read sets, writes the clean sets and the marker READY_02
sbatch --export=ALL,ASM=hw2,FASTA=$WORK/asm/hw2/final.fasta jobs/02_screen_contigs.sbatch   # contigs of one assembly
bash scripts/02b_versions.sh                      # writes envs/versions_02b.tsv, records the databases in envs/databases.tsv
```

The read job does not wait: it stops with a message if the marker of the read-set step (`READY_02A`) is missing. Without a scheduler, run `bash jobs/02_screen_reads.sbatch` after exporting the variables of `config/config.sh`. The tool environment (`$SCREEN_BIN`: minimap2, seqkit, pigz, Python with pandas and numpy) is created with micromamba; versions are in `envs/versions_02b.tsv`.

Cost: elapsed time and peak memory of each job are in the job accounting (`sacct`) and the log folder. In the run reported here, the screen of both read sets took a few minutes on 16 cores (peak memory a few tens of gigabytes, the size of the largest index), and the screen of one set of contigs of 50 million bases about as long as one part of the read screen; building the four indexes took about ten minutes.

### Reading the outputs

* `per_read.tsv.gz` (and `per_contig.tsv.gz`): `frac_<group>` is the fraction of the length covered by counted alignments to that group; `frac_contaminant_any` is the fraction covered by any contaminant group (overlaps counted once); `best_contaminant_organism` is the reference of the group with the largest covered fraction. The name of this organism is the closest entry of the database, not the identification of the contaminant: a read from an unsequenced bacterium is labelled with its nearest relative in the collection.
* `by_organism.tsv`: which references account for the excluded reads, and which for the reads that carry a contaminant majority but a fungal match. A concentration on one or two references (for example a cloning vector) points to a single source of contamination; many references with a few reads each suggest chance matches.
* For contigs, the output has the same layout. A contig of class `excluded` is a candidate contaminant; a contig of class `contaminant_majority_but_fungal_match_kept` needs a look at the two fractions (a contig that is mostly contaminant-like and partly fungal can be a repeat, a ribosomal or mitochondrial sequence, or a contaminant that carries a fungal-like gene). This step only flags contigs; the removal of the contigs it excludes from an assembly is step 05c. Hw 2.0 is analysed as published and nothing is removed from it.

### Limits

* Sensitivity depends on the reference collection (see the self-test); absence of a flag is not proof of absence of contamination. Reads of contaminants with no relative within about 10 % divergence in RefSeq stay in the data.
* The fungal collection holds one genome per genus and no genome of the genus *Hortaea*; most real reads therefore have no fungal match, and the fungal protection acts mainly on conserved or repeated sequence.
* UniVec holds many short adapter and linker sequences; matches shorter than 300 bases are ignored, so only long vector sequences (whole plasmids) cause an exclusion.
* The self-test uses a random 2 % sample of the reads, only to test the scripts and thresholds; the production screen used every read.
* The screen of the contigs of Hw 2.0 (`results/02_pacbio_reads/screen_contigs/hw2/`) was run as a test of the contig script and is descriptive; the interpretation of flagged contigs belongs to the comparison steps.

### References

* Li H (2018) Minimap2: pairwise alignment for nucleotide sequences. Bioinformatics 34:3094-3100. doi:10.1093/bioinformatics/bty191
* Nurk S, Koren S, Rhie A, et al. (2022) The complete sequence of a human genome. Science 376:44-53. doi:10.1126/science.abj6987

(authors, year, volume, pages and DOI checked against Crossref)
