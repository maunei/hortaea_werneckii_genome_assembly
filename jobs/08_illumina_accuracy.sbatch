#!/bin/bash
#SBATCH --job-name=hw_08_illumina_accuracy
#SBATCH --account=<ACCOUNT>
#SBATCH --time=03:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 08_illumina_accuracy
set -euo pipefail

# Step 08: Illumina reads of 2013 mapped to one assembly: genotype check and base accuracy (plan, section 6, line 5).
# Usage (from the package folder):
#   sbatch --export=ALL,ASM=proc_r1,FASTA=$WORK/asm/proc_r1/final.fasta jobs/08_illumina_accuracy.sbatch
# Without a scheduler: ASM=... FASTA=... SLURM_CPUS_PER_TASK=8 bash jobs/08_illumina_accuracy.sbatch   (from the package folder)
# Parameters: ASM (name of the assembly), FASTA (its nucleotide FASTA).
# Optional (defaults are the settings of the plan; the first four exist to run the tests on a subsample):
#   R1, R2 (read files), OUTDIR, MAPDIR, MIN_DEPTH (10), DEPTH_FACTOR (2), MIN_MAPQ (30), MIN_BASEQ (25), MIN_ALT_FRACTION (0.9), MIN_QUAL (30)

: "${ASM:?set ASM (assembly name)}"; : "${FASTA:?set FASTA (assembly FASTA)}"
THREADS="${SLURM_CPUS_PER_TASK:-8}"
READS_DIR="$WORK/reads/illumina2013"
if [ -z "${R1:-}" ]; then
  [ -e "$READS_DIR/READY_03" ] || { echo "ERROR: $READS_DIR/READY_03 is missing: step 03 has not finished" >&2; exit 1; }
  R1="$READS_DIR/SRR866616_1.fastq.gz"; R2="$READS_DIR/SRR866616_2.fastq.gz"
fi
R2="${R2:?set R2 together with R1}"
OUTDIR="${OUTDIR:-$RESULTS/08_illumina_accuracy/$ASM}"
MAPDIR="${MAPDIR:-$WORK/map/illumina2013/$ASM}"
MIN_DEPTH="${MIN_DEPTH:-10}"; DEPTH_FACTOR="${DEPTH_FACTOR:-2}"; MIN_MAPQ="${MIN_MAPQ:-30}"; MIN_BASEQ="${MIN_BASEQ:-25}"
MIN_ALT_FRACTION="${MIN_ALT_FRACTION:-0.9}"; MIN_QUAL="${MIN_QUAL:-30}"
for f in "$FASTA" "$R1" "$R2"; do [ -s "$f" ] || { echo "ERROR: missing or empty $f" >&2; exit 1; }; done
mkdir -p "$OUTDIR" "$MAPDIR"
export PATH="$VAR_BIN:$PATH"
echo "ASM=$ASM FASTA=$FASTA R1=$R1 R2=$R2 THREADS=$THREADS OUTDIR=$OUTDIR MAPDIR=$MAPDIR"
echo "thresholds: MAPQ>=$MIN_MAPQ BASEQ>=$MIN_BASEQ depth>=$MIN_DEPTH depth<=${DEPTH_FACTOR}x median, non-reference fraction>=$MIN_ALT_FRACTION, QUAL>=$MIN_QUAL"
: > "$OUTDIR/timing.tsv"; printf 'stage\tseconds\n' >> "$OUTDIR/timing.tsv"
T0=$SECONDS; stage() { printf '%s\t%s\n' "$1" "$((SECONDS - T0))" >> "$OUTDIR/timing.tsv"; echo "[$(date +%T)] done: $1 ($((SECONDS - T0)) s)"; T0=$SECONDS; }
cd "$MAPDIR"

# 1. reference and index (bwa index, samtools faidx). The FASTA is copied so that the index lives next to the alignments.
cp "$FASTA" ref.fa
bwa index ref.fa 2> bwa_index.log
samtools faidx ref.fa
stage index

# 2. mapping of all read pairs (bwa-mem), sorted BAM. Written under a temporary name and renamed when complete.
bwa mem -t "$THREADS" -R '@RG\tID:illumina2013\tSM:EXF2000\tPL:ILLUMINA' ref.fa "$R1" "$R2" 2> bwa_mem.log \
  | samtools sort -@ 4 -m 2G -T "$MAPDIR/sort_tmp" -O bam -o sorted.bam.tmp -
mv sorted.bam.tmp sorted.bam
samtools index -@ "$THREADS" sorted.bam
stage map

# 3. mapping statistics
samtools flagstat -@ "$THREADS" -O json sorted.bam > flagstat.json
samtools stats -@ "$THREADS" sorted.bam > samstats.txt
{ samtools view -@ "$THREADS" -c -F 0x900 sorted.bam; samtools view -@ "$THREADS" -c -F 0x904 -q "$MIN_MAPQ" sorted.bam; } | tr '\n' ' ' > mapq30_counts.txt
stage mapping_statistics

# 4. depth in windows of 1 kb (mapping quality filter), median window depth, depth limits, callable positions
mosdepth -t 4 --mapq "$MIN_MAPQ" --by 1000 -n w sorted.bam
HI=$("$PY" "$HW/scripts/08_illumina_accuracy.py" depth-limits --regions w.regions.bed.gz --out depth_limits.json --min-depth "$MIN_DEPTH" --factor "$DEPTH_FACTOR")
HI1=$((HI + 1))      # mosdepth bins are [low, high): depth 10 up to HI inclusive is the bin 10:HI1
mosdepth -t 4 --mapq "$MIN_MAPQ" -n --quantize "0:${MIN_DEPTH}:${HI1}:" q sorted.bam
zcat q.quantized.bed.gz | awk -v lab="${MIN_DEPTH}:${HI1}" '$4==lab {print $1"\t"$2"\t"$3}' > callable.bed
[ -s callable.bed ] || { echo "ERROR: no callable position" >&2; exit 1; }
stage callable

# 5. calls: bcftools haploid calling on the callable positions, one group of whole contigs per process
rm -f chunk_*.bed chunk_*.vcf.gz
NCH=$("$PY" "$HW/scripts/08_illumina_accuracy.py" chunks --callable callable.bed --prefix chunk_ --n "$THREADS")
call_chunk() {
  local b="$1"; local o="${b%.bed}.vcf.gz"
  bcftools mpileup -f ref.fa -q "$MIN_MAPQ" -Q "$MIN_BASEQ" -d 1000 -L 1000 -a FORMAT/AD,FORMAT/DP -R "$b" -Ou sorted.bam 2> "${b%.bed}.mpileup.log" \
    | bcftools call -m -v --ploidy 1 -Ou 2> "${b%.bed}.call.log" \
    | bcftools norm -f ref.fa -c w -Ou 2> "${b%.bed}.norm.log" \
    | bcftools view -i "QUAL>=$MIN_QUAL" -Oz -o "$o"
}
export -f call_chunk; export MIN_MAPQ MIN_BASEQ MIN_QUAL
ls chunk_*.bed | xargs -P "$THREADS" -I{} bash -c 'call_chunk {}'
bcftools concat -Oz -o calls.vcf.gz chunk_*.vcf.gz
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t[%AD]\t[%DP]\n' calls.vcf.gz > calls.tsv
echo "calls (QUAL>=$MIN_QUAL, before the filter on the fraction of reads): $(wc -l < calls.tsv)"
stage calling

# 6. differences, genotype check, tables
"$PY" "$HW/scripts/08_illumina_accuracy.py" summarize --asm "$ASM" --fasta ref.fa --calls calls.tsv --callable callable.bed \
  --flagstat flagstat.json --samstats samstats.txt --mapq30 mapq30_counts.txt --depth-limits depth_limits.json \
  --mosdepth-summary w.mosdepth.summary.txt --outdir "$OUTDIR" --min-depth "$MIN_DEPTH" --min-alt-fraction "$MIN_ALT_FRACTION" \
  --min-mapq "$MIN_MAPQ" --min-baseq "$MIN_BASEQ" --min-qual "$MIN_QUAL"
cp depth_limits.json "$OUTDIR/"
stage summary
hw_end 08_illumina_accuracy
