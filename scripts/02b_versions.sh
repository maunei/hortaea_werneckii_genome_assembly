#!/bin/bash
# Writes envs/versions_02b.tsv (programs of the contaminant screen, versions read from the programs) and adds the
# entries of the screen databases to envs/databases.tsv (checksums read from the files made by fetch_screen_databases.sh).
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
OUT="$HW/envs/versions_02b.tsv"
printf 'program\tversion\tenvironment\tpurpose\n' > "$OUT"
add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$OUT"; }
add minimap2 "$("$SCREEN_BIN/minimap2" --version)" '$SCREEN_BIN' "alignment of reads (preset map-pb) and contigs (preset asm20) to the screen database"
add seqkit "$("$SCREEN_BIN/seqkit" version | cut -d' ' -f2)" '$SCREEN_BIN' "read lengths, removal of excluded reads, counts"
add pigz "$("$SCREEN_BIN/pigz" --version 2>&1 | cut -d' ' -f2)" '$SCREEN_BIN' "compression of the filtered alignments"
add python "$("$SCREEN_BIN/python" --version | cut -d' ' -f2)" '$SCREEN_BIN' "classification of reads and contigs (scripts/screen_classify.py), selection of reference genomes, test reads"
add numpy "$("$SCREEN_BIN/python" -c 'import numpy; print(numpy.__version__)')" '$SCREEN_BIN' "simulation of test reads"
add pandas "$("$SCREEN_BIN/python" -c 'import pandas; print(pandas.__version__)')" '$SCREEN_BIN' "selection of reference genomes from the RefSeq assembly summary"
add curl "$(curl --version | head -1 | cut -d' ' -f2)" 'system' "download of the screen databases"
echo "written: $OUT"
# databases
DB="$HW/envs/databases.tsv"; S="$SCREEN_DB"; d="$(date +%F)"
# small descriptors of the screen database for the results folder (sequences and bases per part, manifest of organisms)
if [ -s "$S/parts_stats.tsv" ]; then
  R="$HW/results/02_pacbio_reads/screen_db"; mkdir -p "$R"
  sed 's#[^\t]*/##' "$S/parts_stats.tsv" > "$R/parts_stats.tsv"; cp "$S/refseq_release.txt" "$R/"; gzip -c "$S/screen_manifest.tsv" > "$R/screen_manifest.tsv.gz"
fi
[ -s "$S/parts.md5" ] || { echo "no $S/parts.md5; databases not recorded"; exit 0; }
# append-only (the file is shared with other steps): entries are written once
if grep -q '^screen_db_' "$DB"; then echo "database entries already in $DB"; exit 0; fi
rel="$(cat "$S/refseq_release.txt")"
for part in bacteria_1 bacteria_2 fungi other; do
  md5=$(awk -v f="$part.fa.gz" '$2==f{print $1}' "$S/parts.md5")
  case $part in
    bacteria_1|bacteria_2) src="NCBI RefSeq genomes (https://ftp.ncbi.nlm.nih.gov/genomes/refseq/, one per bacterial genus, list in envs/screen_genomes.tsv; part ${part#bacteria_} of 2)"; use="step 02b: contaminant screen of reads and contigs (bacteria)";;
    fungi) src="NCBI RefSeq genomes (one per fungal genus, list in envs/screen_genomes.tsv; Hortaea excluded)"; use="step 02b: fungal match that protects reads and contigs from exclusion";;
    other) src="NCBI RefSeq genomes (one per archaeal genus), NCBI RefSeq viral release file viral.1.1.genomic.fna.gz, human T2T-CHM13v2.0 (analysis set, https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/), UniVec (https://ftp.ncbi.nlm.nih.gov/pub/UniVec/UniVec)"; use="step 02b: contaminant screen (archaea, viruses, human, vectors)";;
  esac
  printf 'screen_db_%s\t%s\tRefSeq release %s; fasta part %s.fa.gz\t%s\t%s\t%s\n' "$part" "$src" "$rel" "$part" "$d" "$md5" "$use" >> "$DB"
done
for f in chm13v2.0.fa.gz viral.fna.gz UniVec; do
  md5=$(awk -v f="$f" '{n=split($2,a,"/"); if(a[n]==f) print $1}' "$S/sources.md5")
  printf 'screen_db_source_%s\tdownloaded source file of the part "other"\t%s\t%s\t%s\tstep 02b: checksum of the original file\n' "$f" "$f" "$d" "$md5" >> "$DB"
done
printf 'screen_db_genome_list\tenvs/screen_genomes.tsv of this package (genomes chosen by scripts/select_screen_genomes.py from assembly_summary_refseq.txt, RefSeq release %s)\tselection table\t%s\t%s\tstep 02b: exact list of assemblies, reused when the databases are fetched again\n' "$rel" "$d" "$(md5sum "$HW/envs/screen_genomes.tsv" | cut -d' ' -f1)" >> "$DB"
echo "databases recorded in $DB"
