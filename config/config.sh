# Settings shared by all scripts of the package (source this file). Locations are read from environment variables when they are set.
# HW_WORK: work folder for large intermediate files (reads, alignments, assemblies); HW_ENVS: folder of the software environments (tools are called by path, no activation).
export HW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export INPUT="$HW/input"
export RESULTS="${HW_RESULTS:-$HW/results}"
export LOGS_BASE="$HW/logs"
export WORK="${HW_WORK:?set HW_WORK to the folder for large intermediate files (see the README, step 0)}"
export ENVS="${HW_ENVS:?set HW_ENVS to the folder of the software environments (see the README, step 0)}"
export DBS="${HW_DBS:?set HW_DBS to the folder of the reference databases (see the README, step 0)}"      # reference databases (contaminant screen, BUSCO lineage, proteins)
export ACCOUNT="${HW_ACCOUNT:-}"
export GENOME_SIZE=50000000                                      # bases; the length of Hw 2.0 rounded to 50 Mb
export LC_ALL=C
unset PYTHONSAFEPATH
# Software environments (one folder each; the README lists programs and versions)
export QC_BIN="$ENVS/04_I_qc/bin"            # seqkit, samtools, mosdepth, minimap2, fastp
export MODERN_BIN="$ENVS/04_pacbio_modern/bin"   # Canu, Flye, minimap2, samtools, meryl
export HDF5_BIN="$ENVS/04_pacbio_hdf518/bin"     # bax2bam
export LEGACY_BIN="$ENVS/04_pacbio_legacy/bin"   # BLASR, pbdagcon
export RNA_BIN="$ENVS/04_A_rna/bin"              # STAR, SRA Toolkit (fasterq-dump), featureCounts
export VAR_BIN="$ENVS/04_I_var/bin"              # bwa, samtools, bcftools, mosdepth
export PY="$ENVS/04_probe/bin/python"            # Python for the scripts
export LEGACY_LIBS="$ENVS/libcompat_r2"          # compatibility libraries needed by the legacy PacBio programs
# Added by step 07 (comparator and mitochondrial genome)
export BLAST_BIN="$ENVS/04_B_qc/bin"             # miniprot, BLAST+ (tblastn, blastn), bedtools, Entrez Direct
# Added by step 06 (tests of lines 1 to 4)
export BUSCO_BIN="$ENVS/04_B_qc/bin"             # busco, miniprot (BUSCO needs this folder on PATH to find its helpers), samtools, minimap2
export BUSCO_LINEAGE="$DBS/busco_downloads/lineages/fungi_odb10"   # BUSCO lineage (offline use)
export SWISSPROT_FUNGI="$DBS/proteins/swissprot_fungi.faa"          # reviewed UniProt entries of Fungi
export TRINITY_BIN="$ENVS/04_B_trinity/bin"        # Trinity 2.5.1 (de novo transcript assembly; brings Jellyfish, Bowtie2, Samtools, Java)
# Step 02b (contaminant screen): environment with minimap2, seqkit, pigz, pandas and the index files of the screen databases
export SCREEN_BIN="$ENVS/04_screen/bin"                          # minimap2 2.31, seqkit, pigz, python 3.12 with pandas
export SCREEN_DB="${HW_SCREEN_DB:-$DBS/screen}"                  # four FASTA parts (+ .mmi indexes) and manifest, made by scripts/fetch_screen_databases.sh
