#!/bin/bash
#SBATCH --job-name=hw_06_tests
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 06_tests

# Step 06: tests of lines 1 to 4 of one assembly (plan, section 6).
# Parameters (sbatch --export=ALL,...):
#   ASM        name of the assembly (proc_r1_raw, proc_r1, proc_r2, proc_r3, ctrl_canu, ctrl_flye, hw2)      required
#   FASTA      nucleotide FASTA of the assembly                                                              default $WORK/asm/$ASM/final.fasta
#   PB_READS   PacBio reads for the read-back and the depth (FASTQ)                                          default $WORK/reads/pacbio/hq_clean.fastq
#   RNA_DIR    folder of the RNA-seq FASTQ files RUN_1.fastq.gz and RUN_2.fastq.gz                           default $WORK/reads/rna
#   RNA_RUN    RNA-seq run aligned with STAR                                                                 default SRR5086622
#   RES_OUT    folder of the tables                                                                          default $RESULTS/06_tests/$ASM
#   BIG_OUT    folder of the large files (alignments, index)                                                 default $WORK/tests/$ASM
#   STAR_BAM   1 = keep the STAR alignments as a sorted BAM file (large); default 0 = counts only
#   FORCE      1 = redo steps that are already finished (markers in $BIG_OUT/steps)
# Exact command from the package folder:   sbatch --export=ALL,ASM=hw2 jobs/06_tests.sbatch
# Without a scheduler:                      ASM=hw2 bash jobs/06_tests.sbatch      (16 cores and 32 GB of memory are used)
ASM="${ASM:?set ASM}"
FASTA="${FASTA:-$WORK/asm/$ASM/final.fasta}"
PB_READS="${PB_READS:-$WORK/reads/pacbio/hq_clean.fastq}"
RNA_DIR="${RNA_DIR:-$WORK/reads/rna}"; RNA_RUN="${RNA_RUN:-SRR5086622}"
RES="${RES_OUT:-$RESULTS/06_tests/$ASM}"; BIG="${BIG_OUT:-$WORK/tests/$ASM}"
STAR_BAM="${STAR_BAM:-0}"; FORCE="${FORCE:-0}"
THREADS="${SLURM_CPUS_PER_TASK:-16}"
mkdir -p "$RES" "$BIG/steps" "$LOGDIR"
TMP="$(mktemp -d "${SLURM_TMPDIR:-$BIG}/hw06_${ASM}_XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
SCR="$HW/scripts"; TIMEV=/usr/bin/time
MM2="$QC_BIN/minimap2"; SAMTOOLS="$QC_BIN/samtools"; MOSDEPTH="$QC_BIN/mosdepth"; STAR="$RNA_BIN/STAR"; MINIPROT="$BUSCO_BIN/miniprot"
echo "assembly: $ASM  fasta: $FASTA  reads: $PB_READS  rna: $RNA_DIR/${RNA_RUN}_{1,2}.fastq.gz  threads: $THREADS"
[ -s "$FASTA" ] || { echo "no assembly file $FASTA" >&2; exit 2; }
[ -s "$PB_READS" ] || { echo "no PacBio reads $PB_READS (step 02 marker READY_02 must exist)" >&2; exit 2; }
for m in 1 2; do [ -s "$RNA_DIR/${RNA_RUN}_$m.fastq.gz" ] || { echo "no RNA-seq file $RNA_DIR/${RNA_RUN}_$m.fastq.gz (step 03 marker READY_03 must exist)" >&2; exit 2; }; done
[ -s "$BUSCO_LINEAGE/dataset.cfg" ] && [ -s "$SWISSPROT_FUNGI" ] || { echo "databases missing: run scripts/06_fetch_databases.sh on a computer with internet access" >&2; exit 2; }
[ -s "$RES/timings.tsv" ] || printf 'step\tseconds\tmax_rss_gb_largest_process\n' > "$RES/timings.tsv"
FAILED=""

# tm NAME COMMAND...   runs one program, records its wall time and the peak memory of the program (GNU time) in timings.tsv
tm() { local n="$1"; shift; local t; t="$(mktemp -p "$TMP")"; "$TIMEV" -f '%e %M' -o "$t" "$@"; local rc=$?
  read -r s k < <(tail -n 1 "$t"); printf '%s\t%s\t%s\n' "$n" "$s" "$(awk -v k="$k" 'BEGIN{printf "%.2f", k/1048576}')" >> "$RES/timings.tsv"; return $rc; }
# step NAME FUNCTION   runs FUNCTION in its own shell; skips it when its marker exists; a failure is recorded and the other steps go on
step() { local n="$1" fn="$2"
  if [ -e "$BIG/steps/$n.done" ] && [ "$FORCE" != 1 ]; then echo "[$(date)] step $n: already done, skipped"; return; fi
  echo "[$(date)] step $n: start"; local t0=$SECONDS
  ( set -euo pipefail; "$fn" ) && { touch "$BIG/steps/$n.done"; echo "[$(date)] step $n: done in $((SECONDS - t0)) s"; } || { FAILED="$FAILED $n"; rm -f "$BIG/steps/$n.done"; echo "[$(date)] step $n: FAILED"; }
}

s_contiguity() { tm contiguity "$PY" "$SCR/06_contiguity.py" "$FASTA" "$GENOME_SIZE" "$RES/contiguity"; }
s_telomeres()  { tm telomeres "$PY" "$SCR/06_telomeres.py" "$FASTA" "$RES/telomeres" 400 6; }
s_busco() {
  rm -rf "$TMP/busco_$ASM"
  ( cd "$TMP"; PATH="$BUSCO_BIN:$PATH"; tm busco busco -i "$FASTA" -l "$BUSCO_LINEAGE" -m genome -c "$THREADS" -o "busco_$ASM" --out_path "$TMP" --offline --force ) > "$LOGDIR/busco.log" 2>&1
  cp "$(find "$TMP/busco_$ASM" -name 'short_summary*.txt' | head -1)" "$RES/busco_short_summary.txt"
  cp "$(find "$TMP/busco_$ASM" -name full_table.tsv | head -1)" "$RES/busco_full_table.tsv"
  tm busco_summary "$PY" "$SCR/06_busco_summary.py" "$RES/busco_short_summary.txt" "$RES/busco_full_table.tsv" "$RES/busco"
}
s_readback_align() {
  rm -f "$BIG/readback.bam" "$BIG/readback.bam.bai"
  tm readback_minimap2 "$MM2" -ax map-pb -t "$THREADS" --secondary=no "$FASTA" "$PB_READS" 2> "$LOGDIR/minimap2_readback.log" \
    | tm readback_sort "$SAMTOOLS" sort -@ 4 -m 2G -T "$TMP/sort" -o "$BIG/readback.bam" -
  "$SAMTOOLS" index -@ 4 "$BIG/readback.bam"
}
s_readback_stats() { tm readback_stats "$PY" "$SCR/06_readback.py" "$BIG/readback.bam" "$RES/readback" --samtools "$SAMTOOLS"; }
s_depth() {
  tm depth_mosdepth "$MOSDEPTH" -t 4 --by 1000 -n "$BIG/depth" "$BIG/readback.bam" > "$LOGDIR/mosdepth.log" 2>&1
  cp "$BIG/depth.regions.bed.gz" "$RES/depth_1kb_windows.bed.gz"; cp "$BIG/depth.mosdepth.summary.txt" "$RES/depth_mosdepth_summary.txt"
  tm depth_summary "$PY" "$SCR/06_depth.py" "$BIG/depth.regions.bed.gz" "$RES/depth"
}
s_selfalign() {
  # DNA-level alignment of the contigs against each other; -X leaves out a contig against itself, -N and -p keep secondary alignments (several partners of one region)
  tm selfalign_minimap2 "$MM2" -x asm20 -X -c -N 50 -p 0.3 -t "$THREADS" "$FASTA" "$FASTA" > "$BIG/self.paf" 2> "$LOGDIR/minimap2_self.log"
  tm selfalign_summary "$PY" "$SCR/06_selfalign.py" "$BIG/self.paf" "$FASTA" "$RES/redundancy" 1000
}
s_miniprot() {
  tm miniprot "$MINIPROT" -t "$THREADS" -G 5000 -u --outn=1 "$FASTA" "$SWISSPROT_FUNGI" > "$BIG/miniprot.paf" 2> "$LOGDIR/miniprot.log"
  tm miniprot_summary "$PY" "$SCR/06_miniprot_summary.py" "$BIG/miniprot.paf" "$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1]))['all']['total_bp'])" "$RES/contiguity.json")" "$RES/miniprot" 0.9 0.7
}
s_star() {
  local idx="$TMP/star_index" pre="$BIG/star_${RNA_RUN}_" sa chr
  read -r sa chr < <("$PY" -c "
import json, math, sys
c = json.load(open(sys.argv[1]))['all']; g = c['total_bp']
print(int(min(14, math.floor(math.log2(g) / 2 - 1))), int(min(18, math.floor(math.log2(max(g / c['contigs'], 150))))))" "$RES/contiguity.json")
  mkdir -p "$idx"
  tm star_index "$STAR" --runMode genomeGenerate --runThreadN "$THREADS" --genomeDir "$idx" --genomeFastaFiles "$FASTA" --genomeSAindexNbases "$sa" --genomeChrBinNbits "$chr" --outFileNamePrefix "$TMP/star_gen_" > "$LOGDIR/star_index.log" 2>&1
  local out="--outSAMtype None"; [ "$STAR_BAM" = 1 ] && out="--outSAMtype BAM SortedByCoordinate --limitBAMsortRAM 20000000000"
  # all read pairs; introns and the gap between the two mates limited to 5,000 bases; up to 20 places per read
  tm star_align "$STAR" --runThreadN "$THREADS" --genomeDir "$idx" --readFilesIn "$RNA_DIR/${RNA_RUN}_1.fastq.gz" "$RNA_DIR/${RNA_RUN}_2.fastq.gz" --readFilesCommand zcat \
    $out --outFilterMultimapNmax 20 --alignIntronMax 5000 --alignMatesGapMax 5000 --outTmpDir "$TMP/star_tmp" --outFileNamePrefix "$pre" > "$LOGDIR/star_align.log" 2>&1
  cp "${pre}Log.final.out" "$RES/star_Log.final.out"; gzip -c "${pre}SJ.out.tab" > "$RES/star_SJ.out.tab.gz"
  tm star_summary "$PY" "$SCR/06_star_summary.py" "${pre}Log.final.out" "${pre}SJ.out.tab" "$RES/star"
}

step contiguity s_contiguity
step telomeres s_telomeres
step busco s_busco
step readback_align s_readback_align
step readback_stats s_readback_stats
step depth s_depth
step selfalign s_selfalign
step miniprot s_miniprot
step star s_star

# collect all measures into summary.json and summary.tsv
"$PY" "$SCR/06_collect.py" "$RES" "$ASM" "$PB_READS" "$RNA_RUN" "${FAILED# }" || FAILED="$FAILED collect"
echo "failed steps: ${FAILED:-none}"
[ -z "$FAILED" ] && echo "[06_tests] all steps finished"
[ -n "${SLURM_JOB_ID:-}" ] && sacct -j "$SLURM_JOB_ID" --format=JobID,Elapsed,TotalCPU,MaxRSS,State -P 2>/dev/null
hw_end 06_tests
[ -z "$FAILED" ]
