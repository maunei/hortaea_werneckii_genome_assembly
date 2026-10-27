#!/bin/bash
# Fetch the reference sequences of the contaminant screen (run on a node with internet access, e.g. the login node)
# and write them as four FASTA parts in $DBS/screen/. Each sequence name becomes  GROUP|KEY|original_id
# (GROUP: bacteria, archaea, fungi, virus, human, vector; KEY: assembly accession, or sequence id for viruses and vectors).
#   bacteria_1, bacteria_2 : one RefSeq genome per bacterial genus (see select_screen_genomes.py)
#   other                  : one genome per archaeal genus, 26 extra species of frequent contaminants and halophiles (column part=extra),
#                            all RefSeq viral genomes, human T2T-CHM13v2.0, UniVec
#   fungi                  : one RefSeq genome per fungal genus (never Hortaea)
# Usage: bash scripts/fetch_screen_databases.sh      (re-running resumes: finished genomes are kept)
set -euo pipefail
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
PYBIN="${PY:-python3}"
S="$DBS/screen"; T="$S/_tmp"; mkdir -p "$S" "$T/genomes"
NCBI="https://ftp.ncbi.nlm.nih.gov"
CHM13="https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz"
JOBS="${FETCH_JOBS:-4}"
log() { echo "[$(date +'%F %T')] $*"; }

# 1. selection of genomes (the list shipped with the package is used when present, so that the same genomes are fetched again)
SEL="$HW/envs/screen_genomes.tsv"
if [ ! -s "$SEL" ]; then
  log "selecting genomes from the current RefSeq assembly summary"
  curl -sS --retry 5 -o "$T/assembly_summary_refseq.txt" "$NCBI/genomes/refseq/assembly_summary_refseq.txt"
  curl -sS --retry 5 -o "$T/taxdump.tar.gz" "$NCBI/pub/taxonomy/taxdump.tar.gz"
  tar -xzf "$T/taxdump.tar.gz" -C "$T" nodes.dmp
  "$PYBIN" "$HW/scripts/select_screen_genomes.py" --summary "$T/assembly_summary_refseq.txt" --nodes "$T/nodes.dmp" --out "$SEL"
fi
cp "$SEL" "$S/screen_genomes.tsv"

# 2. one worker per genome: download, rename sequences, compress; written to a temporary file per genome
worker() {
  set -o pipefail
  acc="$1"; grp="$2"; url="$3"; tmp="$4"
  out="$tmp/genomes/$acc.fa.gz"
  [ -s "$out" ] && exit 0
  url="${url%/}"; base="${url##*/}"
  curl -sS --fail --retry 6 --retry-delay 5 "$url/${base}_genomic.fna.gz" | gzip -dc \
    | awk -v g="$grp" -v a="$acc" '/^>/{ id=substr($1,2); print ">" g "|" a "|" id; next } { print }' \
    | gzip -1 > "$out.part" && mv "$out.part" "$out" || { echo "FAILED $acc" >> "$tmp/failed.txt"; rm -f "$out.part"; }
}
export -f worker
log "downloading genomes ($JOBS in parallel)"
tail -n +2 "$SEL" | awk -F'\t' '{print $1"\t"$2"\t"$9}' \
  | xargs -P "$JOBS" -L 1 bash -c 'worker "$0" "$1" "$2" "'"$T"'"' 
if [ -s "$T/failed.txt" ]; then log "some genomes failed:"; cat "$T/failed.txt"; exit 1; fi

# 3. concatenate into the parts (gzip members can be joined)
log "building parts"
rm -f "$S"/part_*.fa.gz.tmp
# bacteria split into two parts of similar size (by cumulative genome size, in table order)
awk -F'\t' 'NR>1 && $2=="bacteria" && $10=="main"{s+=$8; a[++n]=$1; z[n]=$8} END{h=s/2; c=0; for(i=1;i<=n;i++){c+=z[i]; print a[i]"\t"(c<=h?1:2)}}' "$SEL" > "$T/bact_split.tsv"
: > "$S/bacteria_1.fa.gz.tmp"; : > "$S/bacteria_2.fa.gz.tmp"; : > "$S/fungi.fa.gz.tmp"; : > "$S/other.fa.gz.tmp"
while IFS=$'\t' read -r acc p; do cat "$T/genomes/$acc.fa.gz" >> "$S/bacteria_$p.fa.gz.tmp"; done < "$T/bact_split.tsv"
awk -F'\t' 'NR>1 && $2=="fungi"{print $1}' "$SEL" | while read -r acc; do cat "$T/genomes/$acc.fa.gz" >> "$S/fungi.fa.gz.tmp"; done
awk -F'\t' 'NR>1 && ($2=="archaea" || ($2=="bacteria" && $10=="extra")){print $1}' "$SEL" | while read -r acc; do cat "$T/genomes/$acc.fa.gz" >> "$S/other.fa.gz.tmp"; done

# 4. viruses (RefSeq release file), human (T2T-CHM13v2.0), vectors (UniVec)
log "viruses, human, vectors"
[ -s "$T/viral.fna.gz" ] || curl -sS --fail --retry 6 -o "$T/viral.fna.gz" "$NCBI/refseq/release/viral/viral.1.1.genomic.fna.gz"
[ -s "$T/RELEASE_NUMBER" ] || curl -sS --fail --retry 6 -o "$T/RELEASE_NUMBER" "$NCBI/refseq/release/RELEASE_NUMBER"
[ -s "$T/chm13v2.0.fa.gz" ] || curl -sS --fail --retry 6 -o "$T/chm13v2.0.fa.gz" "$CHM13"
[ -s "$T/UniVec" ] || curl -sS --fail --retry 6 -o "$T/UniVec" "$NCBI/pub/UniVec/UniVec"
gzip -dc "$T/viral.fna.gz" | awk '/^>/{ id=substr($1,2); print ">virus|" id "|" id; next } { print }' | gzip -1 >> "$S/other.fa.gz.tmp"
gzip -dc "$T/chm13v2.0.fa.gz" | awk '/^>/{ id=substr($1,2); print ">human|CHM13v2.0|" id; next } { print }' | gzip -1 >> "$S/other.fa.gz.tmp"
awk '/^>/{ id=substr($1,2); gsub(/\|/,"_",id); print ">vector|" id "|" id; next } { print }' "$T/UniVec" | gzip -1 >> "$S/other.fa.gz.tmp"
for p in bacteria_1 bacteria_2 fungi other; do mv "$S/$p.fa.gz.tmp" "$S/$p.fa.gz"; done

# 5. manifest (key -> group, organism) and checksums
"$PYBIN" - "$SEL" "$T/viral.fna.gz" "$S/screen_manifest.tsv" <<'PY'
import sys, gzip, csv
sel, viral, out = sys.argv[1:4]
with open(out, "w") as o:
    o.write("group\tkey\ttaxid\torganism\n")
    for r in csv.DictReader(open(sel), delimiter="\t", quoting=csv.QUOTE_NONE):
        o.write(f"{r['group']}\t{r['acc']}\t{r['taxid']}\t{r['organism_name']}\n")
    for l in gzip.open(viral, "rt"):
        if l[0] == ">":
            t = l[1:].rstrip().split(" ", 1)
            o.write(f"virus\t{t[0]}\tNA\t{t[1] if len(t) > 1 else 'NA'}\n")
    o.write("human\tCHM13v2.0\t9606\tHomo sapiens (T2T-CHM13v2.0)\n")
PY
# vector keys: sequence names of UniVec
awk '/^>/{ id=substr($1,2); gsub(/\|/,"_",id); d=$0; sub(/^[^ ]* */,"",d); print "vector\t" id "\tNA\t" d }' "$T/UniVec" >> "$S/screen_manifest.tsv"
cp "$T/RELEASE_NUMBER" "$S/refseq_release.txt"
( cd "$S" && md5sum bacteria_1.fa.gz bacteria_2.fa.gz fungi.fa.gz other.fa.gz > parts.md5; md5sum "$T/chm13v2.0.fa.gz" "$T/viral.fna.gz" "$T/UniVec" > sources.md5 )
log "done: $(ls -l "$S"/*.fa.gz | awk '{s+=$5} END{print s/1e9 " GB compressed"}')"
# the temporary per-genome files are kept until the index is built and checked; remove with: rm -r "$S/_tmp/genomes"
