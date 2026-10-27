#!/bin/bash
# Fetches three ribosomal DNA records of Hortaea werneckii (NCBI GenBank) used in step 07 to test whether a sequence is ribosomal DNA.
# JN546122.1 (18S, 1.6 kb), PZ917530.1 (18S, internal transcribed spacers; partial), MH870461.1 (28S, partial; strain CBS 359.66).
# It also fetches the beta-lactamase TEM-1 of Escherichia coli (UniProt P62593, the ampicillin-resistance gene of many cloning vectors) as a marker of vector sequence.
# Output: $DBS/rdna_refs/rdna_hw.fasta and vector_marker_bla.faa ; one line per fetched set in envs/databases.tsv.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
OUT="$DBS/rdna_refs"; mkdir -p "$OUT"; cd "$OUT"
E=https://eutils.ncbi.nlm.nih.gov/entrez/eutils; DATE="$(date +%F)"
: > rdna_hw.fasta
for A in JN546122.1 PZ917530.1 MH870461.1; do
  curl -sf --retry 3 --max-time 120 "$E/efetch.fcgi?db=nuccore&id=$A&rettype=fasta&retmode=text" >> rdna_hw.fasta || { echo "download failed: $A" >&2; exit 1; }
  sleep 0.5
done
grep -c '>' rdna_hw.fasta
curl -sf --retry 3 --max-time 120 "https://rest.uniprot.org/uniprotkb/P62593.fasta" -o vector_marker_bla.faa || { echo "download failed: P62593" >&2; exit 1; }
DBT="$HW/envs/databases.tsv"
( flock 9
  [ -s "$DBT" ] || printf 'name\tsource\tversion_or_accession\tdownload_date\tchecksum_md5\tused_for\n' > "$DBT"
  grep -q '^rdna_refs_hortaea_werneckii' "$DBT" || printf 'rdna_refs_hortaea_werneckii\t%s\t%s\t%s\t%s\t%s\n' "$E/efetch.fcgi?db=nuccore&rettype=fasta (GenBank; 3 records)" "JN546122.1 PZ917530.1 MH870461.1" "$DATE" "$(md5sum rdna_hw.fasta | cut -d' ' -f1)" "step 07: test whether the 22 sequences are ribosomal DNA" >> "$DBT"
  grep -q '^vector_marker_bla_TEM1' "$DBT" || printf 'vector_marker_bla_TEM1\t%s\t%s\t%s\t%s\t%s\n' "https://rest.uniprot.org/uniprotkb/P62593.fasta (UniProt, reviewed)" "UniProt P62593" "$DATE" "$(md5sum vector_marker_bla.faa | cut -d' ' -f1)" "step 07: marker of cloning-vector sequence among the 22 sequences" >> "$DBT"
) 9> "$DBS/.databases.tsv.lock"
