#!/bin/bash
#SBATCH --job-name=hw_fetch_databases
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start fetch_databases
# The reference data are downloaded once and used offline afterwards.
#   1. BUSCO lineage fungi_odb10 and Swiss-Prot fungal proteins (evaluation 2)
#   2. reference collection of the contaminant screen (step 05): about 83 GB written, about 30 minutes with 4 parallel downloads
#   3. the small reference sequences of step 07 (mitochondrial genomes, ribosomal DNA, beta-lactamase marker)
# Both scripts can be run again: finished downloads are kept, and every set is recorded with source, version and checksum in envs/databases.tsv.
bash "$HW/scripts/06_fetch_databases.sh" || exit 3
FETCH_JOBS=4 bash "$HW/scripts/fetch_screen_databases.sh" || exit 4
# 3. reference sequences of step 07 (mitochondrial genomes of five fungi, ribosomal DNA of Hortaea werneckii, the beta-lactamase marker); the steps 07 fetch them when missing
[ -s "$DBS/mito_refs/mito_genomes.fasta" ] && [ -s "$DBS/mito_refs/mito_proteins.faa" ] || bash "$HW/scripts/07_fetch_mito_refs.sh" || exit 5
[ -s "$DBS/rdna_refs/rdna_hw.fasta" ] && [ -s "$DBS/rdna_refs/vector_marker_bla.faa" ] || bash "$HW/scripts/07_fetch_rdna_refs.sh" || exit 6
hw_end fetch_databases
