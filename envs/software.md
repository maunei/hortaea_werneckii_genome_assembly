# Software used by the package

The programs are not installed by the package. They live in ten environments that were made from explicit lock files (`envs/lockfiles/<name>.explicit.txt`: every package with its build and checksum, so the environments can be re-created exactly with `scripts/make_environments.sh`). Jobs call the programs by path (`config/config.sh` names the folders); no environment is activated.

| Variable in `config/config.sh` | Environment | Main programs |
|---|---|---|
| `QC_BIN` | `04_I_qc` | seqkit, samtools, minimap2, mosdepth, fastp, FastQC, MultiQC |
| `MODERN_BIN` | `04_pacbio_modern` | Canu, Flye, minimap2, samtools |
| `HDF5_BIN` | `04_pacbio_hdf518` | bax2bam (needs the older HDF5 library, 1.8) |
| `LEGACY_BIN` and `LEGACY_LIBS` | `04_pacbio_legacy`, `libcompat_r2` | BLASR, pbdagcon, pbalign, Quiver (GenomicConsensus), pbmerge, pbindex (programs of the original protocol; they need `libnsl.so.1`, supplied by a link made by `scripts/make_environments.sh`) |
| `RNA_BIN` | `04_A_rna` | STAR, SRA Toolkit |
| `VAR_BIN` | `04_I_var` | bwa, samtools, bcftools, mosdepth |
| `BUSCO_BIN`, `BLAST_BIN` | `04_B_qc` | BUSCO, miniprot, BLAST+, bedtools |
| `TRINITY_BIN` | `04_B_trinity` | Trinity, Jellyfish, Bowtie2 |
| `SCREEN_BIN` | `04_screen` | minimap2, seqkit, pigz, pandas (contaminant screen) |
| `PY` | `04_probe` | Python 3.11 for the scripts (standard library, NumPy, pandas) |

Versions of the programs actually used, by step: `envs/versions_*.tsv`. Reference data (BUSCO lineage, Swiss-Prot fungal proteins, mitochondrial and ribosomal reference records, the contaminant screen database) are described in `envs/databases.tsv` with source, version and checksum; the genomes of the screen database are listed in `envs/screen_genomes.tsv`. The databases and the environments are kept outside the package folder, in the locations set by `HW_ENVS` and `HW_DBS`, because they are large (the screen database is 83 GB).
