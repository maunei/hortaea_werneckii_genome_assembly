#!/bin/bash
#SBATCH --job-name=hw_01_fetch_inputs
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 01_fetch_inputs

# For a reader who starts from nothing: download the input files into the input folder and verify their archive checksums.
# (In the run reported in the README the files were already present; step 01_check_inputs verifies them.)
mkdir -p "$INPUT/pacbio" "$INPUT/rnaseq" "$INPUT/illumina2013" "$INPUT/hw2"
$PY "$HW/scripts/fetch_archive.py" "$INPUT/manifests/pacbio_files.tsv" "$INPUT/pacbio" 16 || exit 2
$PY "$HW/scripts/fetch_archive.py" "$INPUT/manifests/rna_sra_files.tsv" "$INPUT/rnaseq" 16 || exit 3
$PY "$HW/scripts/fetch_archive.py" "$INPUT/manifests/illumina2013_sra_files.tsv" "$INPUT/illumina2013" 16 || exit 4
# Hw 2.0: the repository of the paper and the NCBI record (the commit used is in input/hw2/github_commit.txt)
[ -d "$INPUT/hw2/github_Hortaea_werneckii" ] || git clone https://github.com/stajichlab/Hortaea_werneckii "$INPUT/hw2/github_Hortaea_werneckii"
git -C "$INPUT/hw2/github_Hortaea_werneckii" checkout "$(cat "$INPUT/hw2/github_commit.txt")" 2>/dev/null
mkdir -p "$INPUT/hw2/ncbi_GCA_002127715.1"
FTP=https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/002/127/715/GCA_002127715.1_HwerPB1
for f in genomic.fna.gz genomic.gff.gz protein.faa.gz cds_from_genomic.fna.gz feature_count.txt.gz feature_table.txt.gz assembly_report.txt assembly_stats.txt fcs_report.txt; do
  [ -s "$INPUT/hw2/ncbi_GCA_002127715.1/GCA_002127715.1_HwerPB1_$f" ] || curl -sSf -o "$INPUT/hw2/ncbi_GCA_002127715.1/GCA_002127715.1_HwerPB1_$f" "$FTP/GCA_002127715.1_HwerPB1_$f" || echo "not downloaded: $f"
done
for f in README.txt md5checksums.txt; do   # the two files of the record that are not named after the assembly
  [ -s "$INPUT/hw2/ncbi_GCA_002127715.1/$f" ] || curl -sSf -o "$INPUT/hw2/ncbi_GCA_002127715.1/$f" "$FTP/$f" || echo "not downloaded: $f"
done
hw_end 01_fetch_inputs
