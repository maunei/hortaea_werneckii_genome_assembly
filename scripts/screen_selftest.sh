#!/bin/bash
# Self-test of the contaminant screen: a small sample of the real reads (the null set: nearly all are fungal) is mixed with simulated
# reads of known origin (positive controls, see simulate_screen_test_reads.py) and screened with the production script.
# The table results/02_pacbio_reads/screen_test/selftest_sensitivity.tsv gives, per kind of control read, the fraction excluded.
# Variables: TEST_REAL_READS (FASTQ with real reads; default: a 2 % random sample of $WORK/reads/pacbio/hq_subreads.fastq),
#            TEST_DIR [$WORK/screen_test]; the genomes of fetch_screen_test_genomes.sh must exist.
set -euo pipefail
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"; source "$HW/scripts/screen_common.sh"
D="${TEST_DIR:-$WORK/screen_test}"; G="$DBS/screen/_tmp/genomes"; SD="$SCREEN_DB"; mkdir -p "$D"
THREADS="${THREADS:-${SLURM_CPUS_PER_TASK:-8}}"
REAL="${TEST_REAL_READS:-$D/real_sample.fastq}"
if [ ! -s "$REAL" ]; then "$SCREEN_BIN/seqkit" sample -p 0.02 -s 11 "${READS_DIR:-$WORK/reads/pacbio}/hq_subreads.fastq" -o "$REAL"; fi
acc() { awk -F'\t' -v p="$1" 'NR>1 && $5 ~ p {print $1; exit}' "$HW/envs/screen_genomes.tsv"; }
ECO=$(acc "^Escherichia coli O157:H7 str. Sakai"); ZYM=$(acc "^Zymoseptoria tritici IPO323"); ARC=$(acc "^Methanobrevibacter ruminantium")
# genomes: if the per-genome files were removed, the parts of the database are used instead
SRCDIR="$G"; [ -s "$G/$ECO.fa.gz" ] || { echo "per-genome files missing in $G"; exit 3; }
"$SCREEN_BIN/python" "$HW/scripts/simulate_screen_test_reads.py" --out "$D/spikes.fastq" --seed 7 \
  --src bacteria_in_db_div0 "$G/$ECO.fa.gz" 200 0 all --src bacteria_in_db_div5 "$G/$ECO.fa.gz" 200 0.05 all \
  --src bacteria_in_db_div10 "$G/$ECO.fa.gz" 200 0.10 all --src bacteria_in_db_div15 "$G/$ECO.fa.gz" 200 0.15 all \
  --src bacteria_in_db_div20 "$G/$ECO.fa.gz" 200 0.20 all \
  --src Ecoli_CFT073_other_strain "$D/NC_004431.1.fa" 200 0 all --src Pseudomonas_stutzeri_other_species_of_genus "$D/NC_009434.1.fa" 200 0 all \
  --src Staphylococcus_haemolyticus_other_species_of_genus "$D/NC_007168.1.fa" 200 0 all \
  --src archaeon_in_db "$G/$ARC.fa.gz" 100 0 all --src virus_T4_in_db "$SD/_tmp/viral.fna.gz" 100 0 NC_000866 \
  --src human_chr21 "$SD/_tmp/chm13v2.0.fa.gz" 200 0 chr21 \
  --src fungus_in_db_div0 "$G/$ZYM.fa.gz" 200 0 all --src fungus_relative_div10 "$G/$ZYM.fa.gz" 200 0.10 all \
  --chimera chimera_bacterium3kb_fungus1.5kb "$G/$ECO.fa.gz" 0 "$G/$ZYM.fa.gz" 0.10 100 3000 1500
cat "$REAL" "$D/spikes.fastq" > "$D/selftest_subreads.fastq"
READS_DIR="$D" SETS=selftest OUT_DIR="$HW/results/02_pacbio_reads/screen_test" TMP_DIR="$D/screen_tmp" MARKER="" THREADS="$THREADS" bash "$HW/scripts/screen_reads.sh"
"$SCREEN_BIN/python" "$HW/scripts/screen_selftest_summary.py" "$HW/results/02_pacbio_reads/screen_test"
