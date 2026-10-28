#!/bin/bash
#SBATCH --job-name=hw_00_preflight
#SBATCH --account=<ACCOUNT>
#SBATCH --time=00:10:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 00_preflight
# Check made by setup_and_run_all.sh (stage check): the job sees the settings, and the programs and databases that the other jobs use can be run from a compute node.
fail=0
for v in HW WORK ENVS DBS RESULTS INPUT; do echo "$v=${!v}"; done
ck() { if [ -e "$1" ]; then echo "ok       $1"; else echo "MISSING  $1"; fail=1; fi; }
for b in "$QC_BIN/seqkit" "$QC_BIN/samtools" "$QC_BIN/minimap2" "$QC_BIN/mosdepth" "$QC_BIN/fastp" "$MODERN_BIN/canu" "$MODERN_BIN/flye" "$HDF5_BIN/bax2bam" \
         "$LEGACY_BIN/blasr" "$LEGACY_BIN/pbdagcon" "$LEGACY_BIN/quiver" "$RNA_BIN/STAR" "$RNA_BIN/fasterq-dump" "$VAR_BIN/bwa" "$VAR_BIN/bcftools" \
         "$BUSCO_BIN/busco" "$BUSCO_BIN/miniprot" "$BLAST_BIN/tblastn" "$TRINITY_BIN/Trinity" "$SCREEN_BIN/minimap2" "$PY" "$LEGACY_LIBS"; do ck "$b"; done
for f in "$BUSCO_LINEAGE" "$SWISSPROT_FUNGI" "$SCREEN_DB/bacteria_1.mmi" "$SCREEN_DB/bacteria_2.mmi" "$SCREEN_DB/fungi.mmi" "$SCREEN_DB/other.mmi" "$INPUT/CHECKSUMS.md5"; do ck "$f"; done
echo "versions: $("$QC_BIN/samtools" --version | head -1); $("$QC_BIN/seqkit" version); $("$PY" --version 2>&1)"
mkdir -p "$WORK" && touch "$WORK/.write_test" && rm "$WORK/.write_test" && echo "ok       work folder is writable" || { echo "NOT WRITABLE  $WORK"; fail=1; }
mkdir -p "$RESULTS" && echo "ok       results folder $RESULTS"
echo "modules: ${HW_MODULES:-none}"
hw_end 00_preflight
[ $fail -eq 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FAILED"; exit 1; }
