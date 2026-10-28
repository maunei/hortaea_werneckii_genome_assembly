#!/bin/bash
#SBATCH --job-name=hw_04_procedure
#SBATCH --account=<ACCOUNT>
#SBATCH --time=24:00:00
#SBATCH --mem=100G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 04_procedure

# Step 04: the HGAP-style procedure (seeds, correction against the seeds, Canu assembly of the corrected reads). RUN (r1, r2, r3) names the run;
# THREADS may be set with --export to give the repeat runs different thread settings (default: the cores of the job). READS is the filtered read set.
RUN=${RUN:?set RUN (r1, r2 or r3)}; READS=${READS:-$WORK/reads/pacbio/filtered_clean.fastq}; GS=${GS:-$GENOME_SIZE}; SEEDCOV=${SEEDCOV:-30}
NT=${THREADS:-${SLURM_CPUS_PER_TASK:-16}}
OUT="$WORK/asm/proc_${RUN}_raw"; R="$RESULTS/04_procedure/proc_${RUN}"; mkdir -p "$OUT" "$R"; T="$OUT/work"; mkdir -p "$T"; cd "$T"
echo "RUN=$RUN READS=$READS GS=$GS SEEDCOV=$SEEDCOV THREADS=$NT"
export LD_LIBRARY_PATH="$LEGACY_LIBS:$LD_LIBRARY_PATH"
P0=$PATH
export PATH="$LEGACY_BIN:$QC_BIN:$P0"
# 1 seeds: the longest reads until SEEDCOV-fold of the genome size
seqkit fq2fa -j 4 "$READS" -o reads.fa; seqkit stats -a -T reads.fa > "$R/reads_stats.tsv"
NEED=$(awk -v c="$SEEDCOV" -v g="$GS" 'BEGIN{printf "%d", c*g}')
seqkit fx2tab -n -l reads.fa | sort -k2,2nr -T "$T" | awk -v need="$NEED" '{c+=$2; print $1; if(c>=need){exit}}' > seed_names.txt
seqkit grep -f seed_names.txt reads.fa -o seeds.fa; seqkit stats -a -T seeds.fa > "$R/seeds_stats.tsv"
echo "seeds: $(grep -c '>' seeds.fa); shortest seed: $(seqkit fx2tab -n -l seeds.fa | sort -k2,2n | head -1 | cut -f2)"
# 2 correction: all reads aligned to the seeds with BLASR (up to 24 alignments per read), consensus per seed with pbdagcon (coverage >= 4, length >= 500)
/usr/bin/time -v blasr reads.fa seeds.fa -m 5 --bestn 24 --nCandidates 24 --minMatch 12 --maxLCPLength 15 --maxScore -1000 --nproc "$NT" --noSplitSubreads --out aln.m5 > "$LOGDIR/blasr.out" 2> "$LOGDIR/blasr.time"; brc=$?; echo "blasr exit $brc"; [ $brc = 0 ] || exit 2
sort -k6,6 -T "$T" --parallel="$NT" aln.m5 > aln.sorted.m5; rm -f aln.m5
# pbdagcon (a program of the original protocol) can stop with a thread error when it runs with many threads; the result of a run that stopped is incomplete, so the run is repeated (three attempts) and the job fails if none succeeds
for attempt in 1 2 3; do
  /usr/bin/time -v pbdagcon -j "$NT" -t 12 -c 4 -m 500 aln.sorted.m5 > corrected.fasta 2> "$LOGDIR/pbdagcon.time"; prc=$?
  echo "pbdagcon exit $prc (attempt $attempt)"; [ $prc = 0 ] && break
  cp "$LOGDIR/pbdagcon.time" "$LOGDIR/pbdagcon_failed_attempt$attempt.time"
done
[ $prc = 0 ] || { echo "pbdagcon failed in three attempts; the corrected reads would be incomplete" >&2; exit 4; }
seqkit stats -a -T corrected.fasta > "$R/corrected_stats.tsv"; cp corrected.fasta "$OUT/corrected.fasta"; cut -f1-9 "$R/corrected_stats.tsv"
# 3 assembly of the corrected reads with Canu (assembly only, corrected-read error limit 0.025)
export PATH="$MODERN_BIN:$QC_BIN:$P0"
/usr/bin/time -v canu -assemble -p canu -d "$OUT/canu_asm" genomeSize=$GS -pacbio-corrected "$OUT/corrected.fasta" useGrid=false maxThreads="$NT" maxMemory=60 stopOnLowCoverage=2 correctedErrorRate=0.025 > "$LOGDIR/canu_asm.out" 2> "$LOGDIR/canu_asm.time"; rc=$?; echo "canu exit $rc"
[ $rc = 0 ] || exit 3
cp "$OUT/canu_asm/canu.contigs.fasta" "$OUT/final.fasta"; seqkit stats -a -T "$OUT/final.fasta" > "$R/assembly_stats.tsv"; cut -f1-9,13,14 "$R/assembly_stats.tsv"
grep -hE "Elapsed|Maximum resident" "$LOGDIR"/*.time > "$R/time_memory.txt"
rm -f "$T/aln.sorted.m5" "$T/reads.fa"
hw_end 04_procedure
