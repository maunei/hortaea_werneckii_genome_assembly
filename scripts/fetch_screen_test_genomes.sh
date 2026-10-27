#!/bin/bash
# Test genomes that are NOT in the screen database (other strains or species than the chosen ones), used to measure the sensitivity of the screen.
# NC_004431.1 Escherichia coli CFT073 (the database holds other E. coli strains: O157:H7 Sakai, K-12 MG1655);
# NC_009434.1 Pseudomonas stutzeri A1501 and NC_007168.1 Staphylococcus haemolyticus JCSC1435 (other species of genera in the database).
set -euo pipefail
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
D="${TEST_DIR:-$WORK/screen_test}"; mkdir -p "$D"
for id in NC_004431.1 NC_009434.1 NC_007168.1; do
  [ -s "$D/$id.fa" ] || { curl -sS --fail --retry 5 "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=$id&rettype=fasta&retmode=text" > "$D/$id.fa"; sleep 1; }
done
ls -l "$D"/NC_*.fa
