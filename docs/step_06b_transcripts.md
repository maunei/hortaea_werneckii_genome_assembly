## Step 06b: de novo transcripts and their alignment to each assembly

### What this step answers

Gene-space completeness (evaluation 2) asks whether the genes of the organism are present in an assembly. One direct way to ask is to take the transcripts that the organism really makes, assembled from RNA-seq (sequencing of RNA) reads, and to align them to the assembly. If a transcript aligns along nearly all of its length with few differences, the gene it comes from is present and its sequence, including the introns it spans, is intact.

The transcripts must not depend on any of the assemblies that are being judged, otherwise the test would favour the assembly that was used to make them. They are therefore assembled once, without any genome (de novo), with Trinity, and the same transcript set is aligned to every assembly.

### Part 1: assembling the transcripts without a genome

Script: `jobs/06_trinity_denovo.sbatch`. It runs once.

| Setting | Value | Reason |
|---|---|---|
| Reads | the first 25,000,000 read pairs of the HiSeq run SRR5086622, in sequencing order | A practical choice, not an impossibility: with 25 million pairs the run takes about an hour and a half and 123 GB of memory (see below), whereas the whole run (175,019,208 pairs, seven times more) would need several times more memory and time (an extrapolation, not measured), which is possible on a large-memory node but is heavy to repeat. A fixed subset in file order is reproducible and does not depend on any choice. The MiSeq run is used for quality control only. |
| Reads are not trimmed | as decided in step 03 | Trinity tolerates adapter remnants at the depth used here; the quality-control reports of step 03 show how much adapter there is. |
| Program | Trinity 2.5.1, 16 threads, 130 GB of memory for k-mer counting (the job requests 180 GB, because the program starts several processes at once) | Trinity first counts k-mers (short words of 25 bases) of the reads with Jellyfish, builds contigs from them (Inchworm), groups the contigs into components (Chrysalis) and resolves each component into transcripts with the read pairs (Butterfly). |
| Working folder | the local disk of the compute node | Trinity writes a very large number of small files, which is slow on shared storage and would use up the file-count quota. Only the transcript file and its gene map are copied back. |
| `--no_version_check` | set | Without it the program asks a web service for the latest version at start; from a compute node this query can fail (no internet access, or a request limit of the service) and then stops the run. |
| Output folder name | contains the word `trinity` but does not end with it | The program refuses an output folder whose name lacks the word `trinity` (a safety check, because it may delete the folder). A name that ends with `trinity` makes it write the transcripts beside the folder as `<folder>.Trinity.fasta`. The script accepts both file names. |

Before Trinity starts, the script checks that exactly 25,000,000 pairs were read from each mate file and that the two mates of every pair carry the same read name; either failure stops the job. It also refuses to start unless the marker file written by step 03 exists.

Run, from the package folder:

```bash
sbatch jobs/06_trinity_denovo.sbatch
```

Output:

- `$WORK/trinity/Trinity.fasta` and `Trinity.fasta.gene_trans_map` (transcripts and the table that assigns each transcript to a gene); large, kept outside the folder.
- `results/06_transcripts/trinity_assembly.json`: number of transcripts, total length, N50, program version, number of pairs, wall time and peak memory of the run.

What to expect: the transcript set holds {{results/06_transcripts/trinity_assembly.json:sequences}} transcripts with a total of {{results/06_transcripts/trinity_assembly.json:total_bases}} bases and an N50 of {{results/06_transcripts/trinity_assembly.json:n50}} bases. Wall time {{results/06_transcripts/trinity_assembly.json:wall_time}} and peak memory {{results/06_transcripts/trinity_assembly.json:peak_memory_gb}} GB are recorded in the same file. Trinity output is not identical from run to run on different computers (threads finish in different order); the numbers differ slightly and the test below is not sensitive to this.

### Part 2: aligning the transcripts to one assembly

Script: `jobs/06_transcript_alignment.sbatch` (counting script `scripts/06_transcript_align_stats.py`). It runs once for each assembly, with the name of the assembly given in the variable `ASM`:

```bash
sbatch --export=ALL,ASM=hw2 jobs/06_transcript_alignment.sbatch
sbatch --export=ALL,ASM=proc_r3 jobs/06_transcript_alignment.sbatch
```

The assembly is read from `$WORK/asm/<ASM>/final.fasta` (another file can be given in `FASTA`). Run time and memory are small compared with the assembly steps (a splice alignment of the transcript set to one assembly on 8 cores; the job requests 8 GB and 1 hour).

#### The aligner and its settings

The transcripts are aligned with minimap2 in its splice mode (`-x splice`). A transcript is the spliced product of a gene, so it aligns to the genome in several blocks (the exons) separated by gaps (the introns). A spliced aligner scores such a long gap as an intron, with a preference for the splice signal GT at the start and AG at the end of the intron, instead of as a very long deletion. The settings are:

- `-G 5000`: the longest intron is 5,000 bases, the same limit that is given to the RNA read aligner STAR in step 06, and long for a fungal intron.
- `-u b`: the splice signal is looked for on both strands, because the RNA-seq libraries are not strand-specific and Trinity gives each transcript an arbitrary orientation.
- `-c`: write the base-level alignment, from which the identity is computed.
- `--secondary=no`: report only the best place for each part of a transcript. Alternative places of a part (for example the second copy of a gene pair) are therefore not counted.

GMAP (a splice aligner designed for transcripts) is present in the Trinity environment, but minimap2 is used because it is also the program of the other steps and because the measures below do not depend on fine splice-site choices.

#### What is measured

For each transcript the alignment pieces are combined:

1. coverage = the number of transcript bases covered by at least one piece, divided by the transcript length;
2. identity = 1 - (mismatches + inserted bases + deleted bases) / aligned columns, pooled over the pieces; introns are not counted as differences;
3. a transcript passes when coverage is at least 0.90 and identity is at least 0.95. This is the proportion reported.

The result file lists, for the transcript set and the assembly: the number of transcripts, the proportion aligned at all, the proportion aligned over at least half of the length, the proportion that passes, the proportion that passes using only the pieces on the single best contig (a transcript spread over two contigs fails this stricter version, which shows fragmentation of the gene by contig ends), the number of passing transcripts that cross at least one intron, and the proportion of genes (Trinity components, taking the longest isoform of each) that pass.

Output, in `results/06_transcripts/<ASM>/`:

- `summary.json`: the numbers above (key `frac_pass_ge90pct_ge95id` is the proportion that passes, `frac_aligned` the proportion aligned at all, `transcripts` the number of transcripts);
- `transcripts.tsv.gz`: one line for each transcript with its length, coverage, identity and best contig.

For Hw 2.0 the values are {{results/06_transcripts/hw2/summary.json:frac_pass_ge90pct_ge95id}} (passing) and {{results/06_transcripts/hw2/summary.json:frac_aligned}} (aligned at all) among {{results/06_transcripts/hw2/summary.json:transcripts}} transcripts; for Hw 2.1 (`proc_r1`) they are {{results/06_transcripts/proc_r1/summary.json:frac_pass_ge90pct_ge95id}} and {{results/06_transcripts/proc_r1/summary.json:frac_aligned}}.

#### How to read the result, and its limits

- All assemblies receive the same transcripts and the same settings, so differences between assemblies are comparable; the absolute proportion is not the proportion of genes present. Some transcripts will never align well: assembly errors of Trinity itself (chimeras of two genes, fragments), transcripts of contaminant organisms in the culture, and transcripts of genes in regions where both copies of a gene pair are similar enough that the aligner places a transcript on one copy with a few more differences than 5 percent.
- The identity threshold of 95 percent is chosen below the base error expected in a well-covered transcript and above the divergence of many gene pairs of this genome (evaluation 4: several percent), so that a transcript that passes is more likely aligned to its own gene than to a similar copy.
- Because the transcripts come from 25 million of 175 million read pairs, genes that are expressed weakly under the culture condition (10 percent NaCl) are missing from the set. The proportion therefore measures the genes that are well expressed. Using all the reads would add weakly expressed genes to the set and is possible with a larger job (change the number of pairs at the top of `jobs/06_trinity_denovo.sbatch`); it would change the absolute proportions but not the principle of the comparison, since every assembly receives the same transcripts.
- The test sees coding sequence and untranslated regions, not intergenic regions, and a transcript covers one gene at a time; it complements, and does not replace, the BUSCO result (Benchmarking Universal Single-Copy Orthologs).
