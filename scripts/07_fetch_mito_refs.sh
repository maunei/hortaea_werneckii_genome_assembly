#!/bin/bash
# Fetches the mitochondrial reference genomes (NCBI RefSeq) used by step 07 to recognise mitochondrial contigs.
# Output (in $DBS/mito_refs): mito_genomes.fasta, mito_proteins.faa (translations of the annotated protein-coding genes), mito_refs.tsv (accession, organism, length, genes, download date).
# The accessions are fixed here: Dothideomycetes (order Capnodiales and relatives of Hortaea werneckii) and Saccharomyces cerevisiae as outgroup.
# A line per accession is appended to envs/databases.tsv (source URL, version, date).
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
OUT="$DBS/mito_refs"; mkdir -p "$OUT"; cd "$OUT"
ACCS="NC_010222.1 NC_044132.1 NC_050879.1 NC_030334.1 NC_001224.1"
E=https://eutils.ncbi.nlm.nih.gov/entrez/eutils
: > mito_genomes.fasta; rm -f gb_*.gb
for A in $ACCS; do
  [ -s "gb_$A.gb" ] || { curl -sf --retry 3 --max-time 120 "$E/efetch.fcgi?db=nuccore&id=$A&rettype=gbwithparts&retmode=text" -o "gb_$A.gb"; sleep 0.5; }
  [ -s "gb_$A.gb" ] || { echo "download failed: $A" >&2; exit 1; }
done
"$PY" "$HW/scripts/07_mito_refs.py" $ACCS
DATE="$(date +%F)"
DBT="$HW/envs/databases.tsv"
( flock 9
[ -s "$DBT" ] || printf 'name\tsource\tversion_or_accession\tdownload_date\tchecksum_md5\tused_for\n' > "$DBT"
while IFS=$'\t' read -r acc org len ngenes; do
  [ "$acc" = accession ] && continue
  grep -q "^mito_ref_genome_${org}"$'\t' "$DBT" || printf 'mito_ref_genome_%s\t%s\t%s\t%s\t%s\t%s\n' "$org" "$E/efetch.fcgi?db=nuccore&id=$acc&rettype=gbwithparts (NCBI RefSeq, $len bases, $ngenes protein-coding genes)" "$acc" "$DATE" "$(md5sum gb_$acc.gb | cut -d' ' -f1)" "step 07: recognition of mitochondrial contigs" >> "$DBT"
done < mito_refs.tsv
) 9> "$DBS/.databases.tsv.lock"
sed -i "s/\$/\t$DATE/;1s/\t$DATE\$/\tdownload_date/" mito_refs.tsv
echo "done"; cat mito_refs.tsv
