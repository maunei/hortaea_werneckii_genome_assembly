#!/bin/bash
# Submits the whole analysis (steps 01 to 09) with the dependencies between the jobs, from the workflow folder:
#   bash scripts/submit_all.sh            submit
#   DRYRUN=1 bash scripts/submit_all.sh   print the commands only
# Before the first run (once; the jobs need internet access, which the compute nodes of the cluster used here have):
#   bash scripts/make_environments.sh                 software (envs/lockfiles)
#   sbatch jobs/02_fetch_databases.sbatch             BUSCO lineage, Swiss-Prot fungal proteins and the reference collection of the contaminant screen
#   sbatch jobs/01_fetch_inputs.sbatch                the input files, unless they are already in input/
# The screen of reads (02_screen_reads) and everything after it waits for the reads and the database index; the tests wait for their assembly.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$HW"; source config/config.sh
LEDGER="${LEDGER:-jobs/submitted_by_submit_all.tsv}"; : > "$LEDGER"
declare -A ID
S() {   # S key "dependency keys (space separated, may be empty)" sbatch-arguments...
  local key="$1" deps="$2"; shift 2; local dep=""
  for d in $deps; do dep="$dep:${ID[$d]}"; done; [ -n "$dep" ] && dep="--dependency=${DEPTYPE:-afterok}$dep"
  if [ -n "$DRYRUN" ]; then echo "sbatch $dep $*"; ID[$key]="<$key>"; return; fi
  local id; id=$(sbatch --parsable $dep "${SBATCH_COMMON[@]}" "$@" | cut -d';' -f1); ID[$key]="$id"; printf "%s\t%s\t%s\t%s\n" "$key" "$id" "${dep#--dependency=}" "$(basename "${@: -1}")" >> "$LEDGER"; echo "$key $id"
}
# 01 inputs; the published assembly Hw 2.0 is made available as $WORK/asm/hw2/final.fasta
[ -n "$DRYRUN" ] && echo "bash scripts/01_prepare_hw2.sh" || bash scripts/01_prepare_hw2.sh
S check_inputs "" jobs/01_check_inputs.sbatch
# 02 PacBio reads, comparison with the deposited file, screen
S pacbio "" --array=0-4 jobs/02_pacbio_reads.sbatch
S merge pacbio jobs/02_merge_reads.sbatch
S deposited merge jobs/02_compare_deposited.sbatch
S dbindex "" jobs/02_screen_db_index.sbatch
S screen_reads "merge dbindex" jobs/02_screen_reads.sbatch
# 03 RNA-seq and Illumina 2013
S conv_miseq "" --export=ALL,RUN=SRR5086621,GROUP=rna,EXPECTED=3333452 --time=01:00:00 --cpus-per-task=8 jobs/03_convert.sbatch
S conv_hiseq "" --export=ALL,RUN=SRR5086622,GROUP=rna,EXPECTED=175019208 --time=08:00:00 --cpus-per-task=16 jobs/03_convert.sbatch
S conv_ill "" --export=ALL,RUN=SRR866616,GROUP=illumina2013,EXPECTED=37667637 --time=04:00:00 --cpus-per-task=16 jobs/03_convert.sbatch
S qc "conv_miseq conv_hiseq conv_ill" jobs/03_qc.sbatch
# 04 and 05: the procedure (three runs with different thread settings) and the controls
S proc_r1 screen_reads --export=ALL,RUN=r1,THREADS=16 jobs/04_procedure.sbatch
S proc_r2 screen_reads --export=ALL,RUN=r2,THREADS=12 --cpus-per-task=12 jobs/04_procedure.sbatch
S proc_r3 screen_reads --export=ALL,RUN=r3,THREADS=8 --cpus-per-task=8 jobs/04_procedure.sbatch
S ctrl_canu screen_reads jobs/04_control_canu.sbatch
S ctrl_flye screen_reads jobs/04_control_flye.sbatch
# 05 polishing with Quiver: alignment of the screened subreads (array, one task per sequencing run), then Quiver; three runs with different thread settings, and the two controls
POL="1:16:32 2:12:24 3:8:16"
for t in $POL; do r=${t%%:*}; rest=${t#*:}; a=${rest%%:*}; q=${rest#*:}
  S align_r$r proc_r$r --export=ALL,RAW=proc_r${r}_raw,OUTNAME=proc_r$r,THREADS=$a --cpus-per-task=$a jobs/05_align_subreads.sbatch
  S polish_r$r align_r$r --export=ALL,RAW=proc_r${r}_raw,OUTNAME=proc_r$r,THREADS=$q --cpus-per-task=$q jobs/05_polish.sbatch
  S remove_r$r polish_r$r --export=ALL,OUTNAME=proc_r$r jobs/05_remove_contaminant_contigs.sbatch
done
for c in canu flye; do
  S align_ctrl_$c ctrl_$c --export=ALL,RAW=ctrl_$c,OUTNAME=ctrl_${c}_quiver jobs/05_align_subreads.sbatch
  S polish_ctrl_$c align_ctrl_$c --export=ALL,RAW=ctrl_$c,OUTNAME=ctrl_${c}_quiver jobs/05_polish.sbatch
  S remove_ctrl_$c polish_ctrl_$c --export=ALL,OUTNAME=ctrl_${c}_quiver jobs/05_remove_contaminant_contigs.sbatch
done
# 06 transcripts without a genome (Trinity), once
S trinity conv_hiseq jobs/06_trinity_denovo.sbatch
# 07a-c comparator: the GenBank files, the 22 sequences and the mitochondrion of Hw 2.0 (needs the screened reads)
S genbank "" jobs/07_genbank_files.sbatch
S mito_hw2 screen_reads --export=ALL,ASM=hw2 jobs/07_mito.sbatch
S the22 "genbank mito_hw2" jobs/07_the22.sbatch
S depth_unscreened "the22" jobs/07_depth_unscreened.sbatch
# tests of every assembly: 06 tests, 06 transcripts, 08 accuracy, 02 contig screen; and Hw 2.0 for comparison
# (assembly name : job that must have finished)
ASMS="proc_r1_raw:proc_r1 proc_r1:remove_r1 proc_r2:remove_r2 proc_r3:remove_r3 ctrl_canu:ctrl_canu ctrl_flye:ctrl_flye ctrl_canu_quiver:remove_ctrl_canu ctrl_flye_quiver:remove_ctrl_flye hw2:"
for pair in $ASMS; do a=${pair%%:*}; dep=${pair#*:}
  S tests_$a "$dep conv_hiseq screen_reads" --export=ALL,ASM=$a jobs/06_tests.sbatch
  S trans_$a "$dep trinity" --export=ALL,ASM=$a jobs/06_transcript_alignment.sbatch
  S acc_$a "$dep conv_ill" --export=ALL,ASM=$a,FASTA=$WORK/asm/$a/final.fasta jobs/08_illumina_accuracy.sbatch
  S scr_$a "$dep" --export=ALL,ASM=$a,FASTA=$WORK/asm/$a/final.fasta jobs/02_screen_contigs.sbatch
done
# comparisons with Hw 2.0, the mitochondrion and the 22 sequences (polished assemblies of the procedure and the controls)
for pair in proc_r1_raw:proc_r1 proc_r1:remove_r1 proc_r2:remove_r2 proc_r3:remove_r3 ctrl_canu:ctrl_canu ctrl_flye:ctrl_flye ctrl_canu_quiver:remove_ctrl_canu ctrl_flye_quiver:remove_ctrl_flye; do a=${pair%%:*}; dep=${pair#*:}
  S shared_$a "acc_$a acc_hw2" --export=ALL,ASM_A=$a,ASM_B=hw2 jobs/08_shared_differences.sbatch
  [ "$a" = proc_r1_raw ] && continue
  S compare_$a "$dep" --export=ALL,A_ASM=$a,B_ASM=hw2 jobs/07_compare_adjudicate.sbatch
  case $a in *_quiver) continue;; esac
  S mito_$a "$dep" --export=ALL,ASM=$a jobs/07_mito.sbatch
  S the22_$a "$dep" --export=ALL,ASM=$a jobs/07_the22_vs_assembly.sbatch
done
# last job: summary tables, figures and verdict, checksums of the three runs, time and memory, the released assembly, and the comparison with the first analysis.
# It starts when all other jobs have ended, whatever their state (afterany): a job of the comparison with Hw 2.0 that failed must not prevent the summary and the release of the assembly.
# The summary lists what is missing; the message job of setup_and_run_all.sh reports FAILED when any job did not complete.
ALL=""; for k in "${!ID[@]}"; do ALL="$ALL $k"; done
DEPTYPE=afterany S summary "$ALL" jobs/09_summary.sbatch
echo "Everything is submitted; the last job (09_summary) runs when all others have ended and writes results/09_summary/ and results/assembly/."
