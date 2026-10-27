#!/bin/bash
# Step 06: fetches the two reference sets of the tests (run on a computer with internet access, e.g. the login node; the tests then run offline).
#   1. BUSCO lineage fungi_odb10 (758 conserved single-copy fungal genes), downloaded with BUSCO itself.
#   2. Swiss-Prot (reviewed UniProt) proteins of Fungi (taxonomy identifier 4751), downloaded through the UniProt REST interface.
# Each entry is appended to envs/databases.tsv (name, source, version, date, md5, use).
set -euo pipefail
HW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$HW/config/config.sh"
TAB="$HW/envs/databases.tsv"; TODAY="$(date +%F)"
mkdir -p "$DBS/busco_downloads" "$DBS/proteins"
[ -s "$TAB" ] || printf 'name\tsource\tversion_or_accession\tdownload_date\tchecksum_md5\tused_for\n' > "$TAB"
add_entry() {  # appends one row under a lock; a row of the same name from an earlier run is replaced, other rows are left as they are
  ( flock 9
    if grep -q -P "^$1\t" "$TAB"; then grep -v -P "^$1\t" "$TAB" > "$TAB.tmp06"; cat "$TAB.tmp06" > "$TAB"; rm -f "$TAB.tmp06"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$TAB" ) 9> "$DBS/.databases.tsv.lock"
}

# 1. BUSCO lineage
if [ ! -s "$BUSCO_LINEAGE/dataset.cfg" ]; then
  PATH="$BUSCO_BIN:$PATH" busco --download fungi_odb10 --download_path "$DBS/busco_downloads"
fi
[ -s "$BUSCO_LINEAGE/dataset.cfg" ] || { echo "BUSCO lineage not found in $BUSCO_LINEAGE" >&2; exit 1; }
CREATED="$(grep -E '^creation_date' "$BUSCO_LINEAGE/dataset.cfg" | cut -d= -f2 | tr -d ' ')"
NBUSCO="$(grep -E '^number_of_BUSCOs' "$BUSCO_LINEAGE/dataset.cfg" | cut -d= -f2 | tr -d ' ')"
SUM="$(cd "$BUSCO_LINEAGE" && find . -type f | sort | xargs md5sum | md5sum | cut -d' ' -f1)"
add_entry busco_lineage_fungi_odb10 "https://busco-data.ezlab.org/v5/data/lineages/ (downloaded with busco --download; ${NBUSCO} BUSCO genes)" "fungi_odb10 created ${CREATED}" "$TODAY" "$SUM" "step 06: BUSCO completeness (md5 of the md5 list of all files of the lineage folder)"

# 2. Swiss-Prot proteins of Fungi
URL='https://rest.uniprot.org/uniprotkb/stream?compressed=false&format=fasta&query=(taxonomy_id:4751)+AND+(reviewed:true)'
if [ ! -s "$SWISSPROT_FUNGI" ]; then
  curl -sS --fail --retry 3 -D "$DBS/proteins/swissprot_fungi.headers.txt" "$URL" -o "$SWISSPROT_FUNGI.part"
  grep -q '^>' "$SWISSPROT_FUNGI.part"
  mv "$SWISSPROT_FUNGI.part" "$SWISSPROT_FUNGI"
fi
REL="$(grep -i '^x-uniprot-release:' "$DBS/proteins/swissprot_fungi.headers.txt" | head -1 | cut -d: -f2 | tr -d ' \r')"
NSEQ="$(grep -c '^>' "$SWISSPROT_FUNGI")"
add_entry swissprot_fungi "UniProt REST interface, query: taxonomy_id:4751 AND reviewed:true (${NSEQ} proteins)" "UniProt release ${REL:-unknown}" "$TODAY" "$(md5sum "$SWISSPROT_FUNGI" | cut -d' ' -f1)" "step 06: proteins aligned with miniprot (proteins found whole, frameshifts, premature stops)"
echo "done: $BUSCO_LINEAGE and $SWISSPROT_FUNGI"
