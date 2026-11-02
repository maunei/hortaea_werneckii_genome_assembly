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
REPO_DIR="$INPUT/hw2/github_Hortaea_werneckii"
export GIT_LFS_SKIP_SMUDGE=1   # the repository stores some large files with git-lfs (18 coverage files, 2.3 GiB) that the workflow never reads: only the small pointer files are taken, and git-lfs is not needed
if [ -d "$REPO_DIR" ] && [ ! -e "$REPO_DIR/.git/HEAD" ]; then rm -rf "$REPO_DIR"; fi
[ -d "$REPO_DIR" ] || git clone https://github.com/stajichlab/Hortaea_werneckii "$REPO_DIR" || exit 5
git -C "$REPO_DIR" checkout "$(cat "$INPUT/hw2/github_commit.txt")" || exit 5
mkdir -p "$INPUT/hw2/ncbi_GCA_002127715.1"
FTP=https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/002/127/715/GCA_002127715.1_HwerPB1
fetch_ncbi() {
  local dst="$1" url="$2"
  [ -s "$dst" ] && return 0
  curl -sSf --retry 5 -o "$dst.part" "$url" && mv "$dst.part" "$dst" || { rm -f "$dst.part"; echo "ERROR: not downloaded: $url" >&2; exit 6; }
}
for f in genomic.fna.gz genomic.gff.gz protein.faa.gz cds_from_genomic.fna.gz feature_count.txt.gz feature_table.txt.gz assembly_report.txt assembly_stats.txt fcs_report.txt; do
  fetch_ncbi "$INPUT/hw2/ncbi_GCA_002127715.1/GCA_002127715.1_HwerPB1_$f" "$FTP/GCA_002127715.1_HwerPB1_$f"
done
for f in README.txt md5checksums.txt; do   # the two files of the record that are not named after the assembly
  fetch_ncbi "$INPUT/hw2/ncbi_GCA_002127715.1/$f" "$FTP/$f"
done
hw_end 01_fetch_inputs
