#!/bin/bash
#SBATCH --job-name=hw_03_convert
#SBATCH --account=<ACCOUNT>
#SBATCH --time=08:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 03_convert

# Step 03a: convert one SRA archive file to a pair of compressed FASTQ files and compare the number of pairs with the archive record.
# Parameters (sbatch --export=ALL,RUN=...,GROUP=...,EXPECTED=...):
#   RUN       run accession, e.g. SRR5086622
#   GROUP     sub-folder of the data: rna or illumina2013 (the archive file is $INPUT/<rnaseq|illumina2013>/<RUN>/<RUN>)
#   EXPECTED  number of read pairs in the archive record
#   NEEDED    runs that must all be complete before the folder marker READY_03 is written (default: the runs of GROUP below)
: "${RUN:?RUN is required}" "${GROUP:?GROUP is required}" "${EXPECTED:?EXPECTED is required}"
case "$GROUP" in
  rna)          SRA="$INPUT/rnaseq/$RUN/$RUN";        NEEDED="${NEEDED:-SRR5086621 SRR5086622}" ;;
  illumina2013) SRA="$INPUT/illumina2013/$RUN/$RUN";  NEEDED="${NEEDED:-SRR866616}" ;;
  *) echo "GROUP must be rna or illumina2013" >&2; exit 1 ;;
esac
THREADS="${SLURM_CPUS_PER_TASK:-8}"
OUT="$WORK/reads/$GROUP"; mkdir -p "$OUT"
# node-local temporary folder (fasterq-dump writes several times the size of the final FASTQ files there)
TMPBASE="${SLURM_TMPDIR:-$WORK/tmp_03}"; T="$TMPBASE/$RUN"; mkdir -p "$T/tmp" "$T/out"
trap 'rm -rf "$T"' EXIT
[ -s "$SRA" ] || { echo "missing archive file $SRA" >&2; exit 2; }

# 1. conversion; --split-3 writes mates to RUN_1 and RUN_2 and reads without a mate to RUN.fastq; read names become @RUN.<spot>/1 and /2
"$RNA_BIN/fasterq-dump" "$SRA" --split-3 -e "$THREADS" -t "$T/tmp" \
  --seq-defline '@$ac.$si/$ri' --qual-defline '+' -O "$T/out" > "$LOGDIR/fasterq_$RUN.log" 2>&1 || { echo "fasterq-dump failed" >&2; exit 3; }
ls -l "$T/out"
UNPAIRED=0; [ -s "$T/out/$RUN.fastq" ] && UNPAIRED=$(( $(wc -l < "$T/out/$RUN.fastq") / 4 ))

# 2. compression to temporary names; the final names appear only after the checks pass
for R in 1 2; do pigz -p "$THREADS" -c "$T/out/${RUN}_${R}.fastq" > "$OUT/${RUN}_${R}.fastq.gz.part" || { echo "pigz failed" >&2; exit 4; }; done

# 3. checks: numbers of pairs against the archive record, and identical read names (without /1 /2) in the same order in both files
n1=$("$QC_BIN/seqkit" stats -T -j "$THREADS" "$OUT/${RUN}_1.fastq.gz.part" | tail -1 | cut -f4)
n2=$("$QC_BIN/seqkit" stats -T -j "$THREADS" "$OUT/${RUN}_2.fastq.gz.part" | tail -1 | cut -f4)
cmp <(pigz -dc "$OUT/${RUN}_1.fastq.gz.part" | awk 'NR%4==1{sub(/\/[12]$/,""); print}') \
    <(pigz -dc "$OUT/${RUN}_2.fastq.gz.part" | awk 'NR%4==1{sub(/\/[12]$/,""); print}') > "$LOGDIR/name_check_$RUN.txt" 2>&1 && names=ok || names=MISMATCH
st=ok; { [ "$n1" = "$EXPECTED" ] && [ "$n2" = "$EXPECTED" ] && [ "$names" = ok ]; } || st=FAILED
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$RUN" "$EXPECTED" "$n1" "$n2" "$UNPAIRED" "$names" "$st" | tee "$OUT/$RUN.counts.tsv"
if [ "$st" != ok ]; then echo "COUNT OR NAME MISMATCH: step stopped, FASTQ files left as .part" >&2; exit 5; fi
for R in 1 2; do mv "$OUT/${RUN}_${R}.fastq.gz.part" "$OUT/${RUN}_${R}.fastq.gz"; done

# 4. folder marker once every run of the folder is complete
all=1; for r in $NEEDED; do grep -q "ok$" "$OUT/$r.counts.tsv" 2>/dev/null && [ -s "$OUT/${r}_2.fastq.gz" ] || all=0; done
[ "$all" = 1 ] && touch "$OUT/READY_03" && echo "READY_03 written in $OUT"
hw_end 03_convert
