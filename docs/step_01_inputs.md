## Step 01. Input files and their checksums

### What is checked and why

Every later number depends on the input files being exactly the files of the archives. The workflow keeps its inputs in the folder `input/`: the 15 PacBio files of the five sequencing runs (`.bax.h5`, the raw output of the RS II instrument), the SRA archive files of the two RNA-seq runs and of the Illumina run of 2013, and the published assembly Hw 2.0 as it is stored in the GitHub repository of the paper and in the NCBI record GCA_002127715.1. The commit of the repository that was used is written in `input/hw2/github_commit.txt`.

Two checks are made, and both can be repeated by anyone who uses the same data. First, every archive file is compared with the md5 checksum and the size that the archive itself publishes (`input/manifests/*.tsv`, one table per data group): this shows that the files are the files of the archive. Second, the md5 checksum of every input file used here is listed in `input/CHECKSUMS.md5`, so that another person can compute the checksums of their own copy and compare them with this list, and know that the same data are used as in the results reported below.

### How to run

```bash
cd $HW
sbatch jobs/01_check_inputs.sbatch
```

If the files are not yet in `input/`, run `jobs/01_fetch_inputs.sbatch` first: it downloads the archive files named in the manifests (`scripts/fetch_archive.py`, parallel download with checksum verification), clones the repository of the paper at the recorded commit and downloads the NCBI files. The download is large (about 56 GB for the PacBio files). In the run reported here the files had been downloaded beforehand and only the check was run.

### Output files

* `results/01_inputs/archive_check.tsv`: one row per archive file with the published checksum, the checksum found and the status.
* `results/01_inputs/checksums_failed.txt`: empty when every file agrees with `CHECKSUMS.md5`.
