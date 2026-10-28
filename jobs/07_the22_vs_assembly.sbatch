#!/bin/bash
#SBATCH --job-name=hw_the22_vs_asm
#SBATCH --account=<ACCOUNT>
#SBATCH --time=00:30:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=8
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start the22_vs_asm
# Step 07b: repeats the alignment of the 22 sequences of Hw 2.0 against any other assembly (the contaminant screen of the contigs of an assembly is step 02b, jobs/02_screen_contigs.sbatch).
# Parameters (sbatch --export=ALL,ASM=...,FASTA=...): ASM = assembly name; FASTA = assembly FASTA (default $WORK/asm/$ASM/final.fasta).
: "${ASM:?set ASM}"; FASTA="${FASTA:-$WORK/asm/$ASM/final.fasta}"; THREADS="${SLURM_CPUS_PER_TASK:-8}"
OUT="${OUT:-$RESULTS/07_comparator/the22/vs_assemblies}"; TMP="$WORK/07_comparator/the22_vs_$ASM"; mkdir -p "$OUT" "$TMP"
IDS="$RESULTS/07_comparator/genbank_files/the22_ids.tsv"; [ -s "$IDS" ] || { echo "run jobs/07_genbank_files.sbatch first" >&2; exit 1; }
"$PY" - <<PYEOF
import sys; sys.path.insert(0, "$HW/scripts"); from hw07_common import *
ids = [l.split("\t")[0] for l in open("$IDS").read().splitlines()[1:]]
a = read_fasta("$WORK/asm/hw2/final.fasta"); write_fasta("$TMP/the22.fa", {n: a[n] for n in ids})
PYEOF
EXCL=""; [ "$ASM" = hw2 ] && EXCL=exclude_self
"$PY" "$HW/scripts/07_the22_align.py" "$ASM" "$FASTA" "$TMP/the22.fa" "$OUT" "$THREADS" $EXCL
hw_end the22_vs_asm
