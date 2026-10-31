#!/bin/bash
#SBATCH --job-name=hw_03_qc
#SBATCH --account=<ACCOUNT>
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 03_qc

# Step 03b: quality control of the RNA-seq and Illumina 2013 reads: FastQC (all reads), fastp in report-only mode, MultiQC, summary tables.
# Parameters (all optional): QC_RUNS="RUN:GROUP ..." (default: the three runs), READS (folder with the FASTQ files, default $WORK/reads),
#   QCDIR (reports on scratch), OUT (result tables of the package).
QC_RUNS="${QC_RUNS:-SRR5086621:rna SRR5086622:rna SRR866616:illumina2013}"
READS="${READS:-$WORK/reads}"; QCDIR="${QCDIR:-$WORK/qc/03_rna_illumina}"; OUT="${OUT:-$RESULTS/03_rna_illumina}"
THREADS="${SLURM_CPUS_PER_TASK:-8}"; HALF=$(( THREADS / 2 )); [ "$HALF" -ge 1 ] || HALF=1
mkdir -p "$QCDIR/fastqc" "$QCDIR/fastp" "$QCDIR/tmp" "$OUT/fastp"
export PATH="$QC_BIN:$PATH"

FILES=(); for rg in $QC_RUNS; do r="${rg%%:*}"; g="${rg##*:}"; FILES+=("$READS/$g/${r}_1.fastq.gz" "$READS/$g/${r}_2.fastq.gz"); done
for f in "${FILES[@]}"; do [ -s "$f" ] || { echo "missing $f" >&2; exit 2; }; done

# FastQC on every read of every file (no subsampling is possible: FastQC reads the whole file unless told otherwise), half of the cores
fastqc -t "$HALF" -d "$QCDIR/tmp" --outdir "$QCDIR/fastqc" "${FILES[@]}" > "$LOGDIR/fastqc.log" 2>&1 &
FQ=$!
# fastp without any output file for reads (no -o/-O/--out1/--out2): it only evaluates quality, adapters, duplication and insert size
for rg in $QC_RUNS; do r="${rg%%:*}"; g="${rg##*:}"
  fastp -i "$READS/$g/${r}_1.fastq.gz" -I "$READS/$g/${r}_2.fastq.gz" -w "$HALF" --dup_calc_accuracy 3 \
        -j "$QCDIR/fastp/$r.json" -h "$QCDIR/fastp/$r.html" -R "$r" > "$LOGDIR/fastp_$r.log" 2>&1 || { echo "fastp failed for $r" >&2; kill "$FQ" 2>/dev/null; exit 3; }
done
wait "$FQ" || { echo "FastQC failed" >&2; exit 4; }

multiqc -f -o "$QCDIR/multiqc" "$QCDIR/fastqc" "$QCDIR/fastp" > "$LOGDIR/multiqc.log" 2>&1 || { echo "MultiQC failed" >&2; exit 5; }
cp "$QCDIR/multiqc/multiqc_report.html" "$OUT/multiqc_report.html"
cp "$QCDIR"/fastp/*.json "$OUT/fastp/"
"$PY" "$HW/scripts/03_make_tables.py" "$READS" "$QCDIR" "$OUT" $QC_RUNS || exit 4
cat "$OUT/read_counts.tsv" "$OUT/qc_summary.tsv"
hw_end 03_qc
