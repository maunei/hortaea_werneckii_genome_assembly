#!/bin/bash
#SBATCH --job-name=hw_06_trinity_denovo
#SBATCH --account=<ACCOUNT>
#SBATCH --time=06:00:00
#SBATCH --mem=180G
#SBATCH --cpus-per-task=16
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/modules.sh"      # the modules of settings.yaml
source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 06_trinity_denovo

# Step 06, part 1: transcripts assembled from the RNA-seq reads without any genome (Trinity), the input of the transcript test.
# Reads: the first N_PAIRS read pairs of the HiSeq run, in sequencing order (a fixed subset: the whole run needs more memory and time than one job).
# Output: $TRINITY_OUT/Trinity.fasta (+ gene_trans_map), results/06_transcripts/trinity_assembly.json
# Optional settings (environment variables): RNA_DIR, RUN, N_PAIRS, TRINITY_OUT, MAXMEM_GB, TRINITY_RESULTS.
RNA_DIR="${RNA_DIR:-$WORK/reads/rna}"
RUN="${RUN:-SRR5086622}"
N_PAIRS="${N_PAIRS:-25000000}"
TRINITY_OUT="${TRINITY_OUT:-$WORK/trinity}"
TRINITY_RESULTS="${TRINITY_RESULTS:-$RESULTS/06_transcripts}"
MAXMEM_GB="${MAXMEM_GB:-130}"          # memory limit given to Trinity (Jellyfish k-mer counting); the job requests 180 GB
CPUS="${SLURM_CPUS_PER_TASK:-16}"

# The reads of step 03 must exist (the marker file is written when step 03 has finished).
if [ -z "${SKIP_MARKER:-}" ] && [ ! -e "$RNA_DIR/READY_03" ]; then echo "ERROR: $RNA_DIR/READY_03 is missing; run step 03 first" >&2; exit 2; fi
for m in 1 2; do [ -s "$RNA_DIR/${RUN}_${m}.fastq.gz" ] || { echo "ERROR: $RNA_DIR/${RUN}_${m}.fastq.gz is missing" >&2; exit 2; }; done

# Node-local disk: Trinity writes very many small files, which is slow and wasteful on the shared file system.
T="$(mktemp -d "${SLURM_TMPDIR:-${TMPDIR:-/tmp}}/hw06_trinity.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export PATH="$TRINITY_BIN:$QC_BIN:$PATH"          # Trinity must find its own Perl, Java, Jellyfish, Bowtie2 and Samtools first
mkdir -p "$TRINITY_OUT" "$TRINITY_RESULTS"

# 1. The first N_PAIRS read pairs of each mate file (4 lines per read); the pair count is checked below, so the message of the closed pipe is hidden.
LINES=$(( N_PAIRS * 4 ))
zcat "$RNA_DIR/${RUN}_1.fastq.gz" 2>/dev/null | head -n "$LINES" > "$T/r1.fq" || true     # zcat ends with a broken pipe once head has enough lines; this is expected
zcat "$RNA_DIR/${RUN}_2.fastq.gz" 2>/dev/null | head -n "$LINES" > "$T/r2.fq" || true
P1=$(( $(wc -l < "$T/r1.fq") / 4 )); P2=$(( $(wc -l < "$T/r2.fq") / 4 ))
echo "pairs in subset: mate 1 = $P1, mate 2 = $P2 (requested $N_PAIRS)"
[ "$P1" -eq "$N_PAIRS" ] && [ "$P2" -eq "$N_PAIRS" ] || { echo "ERROR: the run holds fewer pairs than requested or the mates differ" >&2; exit 3; }

# 2. The mates must be in the same order: compare the read names (without /1 and /2) of the whole subset.
BAD=$(paste <(awk 'NR%4==1{print $1}' "$T/r1.fq") <(awk 'NR%4==1{print $1}' "$T/r2.fq") | awk '{a=$1; b=$2; sub(/\/[12]$/,"",a); sub(/\/[12]$/,"",b); if (a!=b) bad++} END{print bad+0}')
echo "read pairs whose two mates have different names: $BAD"
[ "$BAD" -eq 0 ] || { echo "ERROR: mates are not in the same order" >&2; exit 3; }

# 3. Trinity. The output folder name must contain the word 'trinity' (a safety check of the program) and must not end in 'trinity'
#    (otherwise the transcripts are written beside the folder as <folder>.Trinity.fasta); --no_version_check avoids a web query from the compute node.
/usr/bin/time -v Trinity --seqType fq --left "$T/r1.fq" --right "$T/r2.fq" --max_memory "${MAXMEM_GB}G" --CPU "$CPUS" \
    --output "$T/trinity_run" --no_version_check > "$LOGDIR/trinity.out" 2> "$LOGDIR/trinity.time"
rc=$?
echo "Trinity exit status: $rc"
grep -E 'Elapsed|Maximum resident' "$LOGDIR/trinity.time"
[ $rc -eq 0 ] || { tail -20 "$LOGDIR/trinity.out"; exit $rc; }

# 4. Find the transcript file (whichever of the two naming schemes was used) and copy back only the results.
F="$T/trinity_run/Trinity.fasta"
[ -s "$F" ] || F="$T/trinity_run.Trinity.fasta"
[ -s "$F" ] || F="$(find "$T" -maxdepth 2 -name '*Trinity.fasta' -size +0 | head -1)"
[ -s "$F" ] || { echo "ERROR: no transcript file found" >&2; find "$T" -maxdepth 2 | head -30; exit 4; }
echo "transcript file: $F"
cp "$F" "$TRINITY_OUT/Trinity.fasta"
[ -s "${F}.gene_trans_map" ] && cp "${F}.gene_trans_map" "$TRINITY_OUT/Trinity.fasta.gene_trans_map"
cp "$T"/trinity_run/*.log "$LOGDIR/" 2>/dev/null || true

# 5. Check and record: number of transcripts, total length, N50; the version of the program.
grep -c '>' "$TRINITY_OUT/Trinity.fasta"
VERSION=$(ls "${TRINITY_BIN%/bin}/conda-meta" 2>/dev/null | grep -m1 -E '^trinity-[0-9]' | sed -E 's/^trinity-//; s/-[^-]+\.json$//')   # read from the environment (the program does not print it when the version check is off)
ELAPSED=$(grep 'Elapsed (wall clock)' "$LOGDIR/trinity.time" | sed 's/.*: //')                                   # h:mm:ss
MAXRSS_GB=$(grep 'Maximum resident set size' "$LOGDIR/trinity.time" | awk '{printf "%.1f", $NF/1048576}')        # kilobytes to gigabytes
"$PY" "$HW/scripts/06_fasta_stats.py" "$TRINITY_OUT/Trinity.fasta" "$TRINITY_RESULTS/trinity_assembly.json" \
    "trinity_version=$VERSION" "run=$RUN" "read_pairs_used=$N_PAIRS" "max_memory_gb=$MAXMEM_GB" "cpus=$CPUS" "wall_time=$ELAPSED" "peak_memory_gb=$MAXRSS_GB" || exit 4
hw_end 06_trinity_denovo
