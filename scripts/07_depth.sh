#!/bin/bash
# PacBio read depth of an assembly in windows of 1 kb (step 07; same alignment settings for every assembly).
# Usage: scripts/07_depth.sh ASM FASTA READS [THREADS]
#   ASM   name of the assembly (output folder $WORK/07_comparator/<ASM>)
#   FASTA assembly FASTA
#   READS FASTQ of the PacBio reads (the high-quality subreads after the contaminant screen, hq_clean.fastq)
# The reads are aligned with minimap2 (preset map-pb), primary alignments only are counted (mosdepth, windows of 1000 bases).
# Output: $WORK/07_comparator/<ASM>/depth.regions.bed.gz (window means), depth.per_contig.tsv (mean depth per contig, all reads and reads of mapping quality >= 20), reads_vs_asm.bam.
# An existing result is kept (set FORCE=1 to recompute), so that several scripts can share the same alignment.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
ASM="$1"; FASTA="$2"; READS="$3"; THREADS="${4:-${SLURM_CPUS_PER_TASK:-8}}"
D="${DEPTH_DIR:-$WORK/07_comparator/$ASM}"; mkdir -p "$D"
if [ -s "$D/depth.per_contig.tsv" ] && [ -z "$FORCE" ]; then echo "depth already computed: $D"; exit 0; fi
[ -s "$READS" ] || { echo "reads not found: $READS" >&2; exit 2; }
"$QC_BIN/minimap2" -ax map-pb -t "$THREADS" --secondary=no "$FASTA" "$READS" 2> "$D/minimap2.log" \
  | "$QC_BIN/samtools" sort -@ 4 -m 2G -o "$D/reads_vs_asm.bam" - && "$QC_BIN/samtools" index "$D/reads_vs_asm.bam" || exit 3
"$QC_BIN/mosdepth" -t 4 -n --by 1000 --flag 3844 "$D/depth" "$D/reads_vs_asm.bam" || exit 4
# second count with reads of mapping quality 20 or more only (unique placements; reads of repeated regions have quality 0)
"$QC_BIN/mosdepth" -t 4 -n --by 1000 --flag 3844 --mapq 20 "$D/depth_mapq20" "$D/reads_vs_asm.bam" || exit 4
"$QC_BIN/samtools" flagstat -@ 4 "$D/reads_vs_asm.bam" > "$D/flagstat.txt"
# mean depth per contig = total / length from the mosdepth summaries; contigs without any aligned read are listed with depth 0
awk '/^>/{if(n!="")print n"\t"l; n=substr($1,2); l=0; next}{l+=length($0)} END{if(n!="")print n"\t"l}' "$FASTA" > "$D/asm.lengths"
awk 'BEGIN{OFS="\t"; print "contig","length","mean_depth","mean_depth_mapq20"}
     FILENAME==ARGV[1] { if ($1!="total" && $1!="chrom" && $1 !~ /_region$/) d[$1]=$4; next }
     FILENAME==ARGV[2] { if ($1!="total" && $1!="chrom" && $1 !~ /_region$/) q[$1]=$4; next }
     {print $1,$2,($1 in d ? d[$1] : 0),($1 in q ? q[$1] : 0)}' "$D/depth.mosdepth.summary.txt" "$D/depth_mapq20.mosdepth.summary.txt" "$D/asm.lengths" > "$D/depth.per_contig.tsv.tmp" && mv "$D/depth.per_contig.tsv.tmp" "$D/depth.per_contig.tsv"
echo "$READS" > "$D/reads_used.txt"
echo "depth done: $D"
