#!/bin/bash
# FX-17: 02_screen_db_index.sbatch does not rewrite parts_stats.tsv in the databases folder
# when it already exists and is newer than the parts; the descriptor files in results/ are still written.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/dbs/screen" "$W/results" "$W/logs"

cat > "$W/bin/seqkit" <<'M'
#!/bin/bash
echo "seqkit_called" >> "$SEQKIT_LOG"
printf "file\tformat\ttype\tnum_seqs\tsum_len\n"
for f in "$@"; do
  case "$f" in *.fa.gz) printf "%s\tFASTA\tDNA\t10\t1000\n" "$f" ;; esac
done
M
cat > "$W/bin/minimap2" <<'M'
#!/bin/bash
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "-d" ]; then j=$((i+1)); printf "mmi" > "${!j}"; fi
done
M
chmod +x "$W/bin/seqkit" "$W/bin/minimap2"

export SCREEN_DB="$W/dbs/screen" SCREEN_BIN="$W/bin" RESULTS="$W/results" LOGS_BASE="$W/logs" SEQKIT_LOG="$W/seqkit.log"
for p in bacteria_1 bacteria_2 other fungi; do
  printf "fa" > "$SCREEN_DB/$p.fa.gz"
  printf "mmi" > "$SCREEN_DB/$p.mmi"
done
printf "230\n" > "$SCREEN_DB/refseq_release.txt"
printf "group\tkey\ttaxid\torganism\nbacteria\tGCF_1\t1\tE. coli\n" > "$SCREEN_DB/screen_manifest.tsv"

# 1. When parts_stats.tsv is missing, 02_screen_db_index.sbatch must create it and write results/ descriptors
(
  eval "$(sed -n '/^source "\$HW\/scripts\/screen_common.sh"/,/^hw_end/p' "$HW/jobs/02_screen_db_index.sbatch" | grep -v '^hw_end')"
) > "$W/run1.out" 2>&1 || { echo "first run (missing parts_stats.tsv) failed:"; cat "$W/run1.out"; exit 1; }
[ -s "$SCREEN_DB/parts_stats.tsv" ] && [ -s "$RESULTS/02_pacbio_reads/screen_db/parts_stats.tsv" ] || { echo "parts_stats.tsv not created on first run"; exit 1; }

# 2. Make parts_stats.tsv newer than *.fa.gz, make $SCREEN_DB read-only, clear results/, and run again
sleep 1; touch "$SCREEN_DB/parts_stats.tsv"
rm -rf "$RESULTS/02_pacbio_reads/screen_db" "$SEQKIT_LOG"
chmod 555 "$SCREEN_DB"
chmod 444 "$SCREEN_DB/parts_stats.tsv"

(
  eval "$(sed -n '/^source "\$HW\/scripts\/screen_common.sh"/,/^hw_end/p' "$HW/jobs/02_screen_db_index.sbatch" | grep -v '^hw_end')"
) > "$W/run2.out" 2>&1
rc=$?
chmod 755 "$SCREEN_DB"
[ "$rc" -eq 0 ] || {
  echo "FAIL: 02_screen_db_index.sbatch failed (exit $rc) when parts_stats.tsv was already newer than *.fa.gz and SCREEN_DB was read-only:"
  cat "$W/run2.out"
  exit 1
}
[ ! -e "$SEQKIT_LOG" ] || { echo "FAIL: seqkit stats was run again even though parts_stats.tsv was newer than all parts"; exit 1; }
for f in parts_stats.tsv refseq_release.txt screen_manifest.tsv.gz; do
  [ -s "$RESULTS/02_pacbio_reads/screen_db/$f" ] || { echo "FAIL: descriptor $f was not written to results/02_pacbio_reads/screen_db/"; exit 1; }
done
exit 0
