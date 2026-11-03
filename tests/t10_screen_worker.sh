#!/bin/bash
# fetch_screen_databases.sh: the worker that downloads one genome gets its arguments in the right order (mock curl, no network)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$W/bin" "$W/T/genomes"
cat > "$W/bin/curl" <<'M'
#!/bin/bash
# mock: writes a small gzipped FASTA; the URL is recorded
for a in "$@"; do case "$a" in http*) echo "$a" >> "$MOCK_URLS";; esac; done
printf '>seq1 test\nACGT\n' | gzip
M
chmod +x "$W/bin/curl"; export PATH="$W/bin:$PATH" MOCK_URLS="$W/urls"
printf 'acc\tgroup\tkey\ttaxid\torg\tlevel\tcat\tsize\tftp_path\tpart\nGCF_1.1\tbacteria\tk\t1\to\tc\tr\t5\thttps://example.org/a/GCF_1.1_x\tmain\nGCF_2.1\tfungi\tk\t2\to\tc\tr\t5\thttps://example.org/b/GCF_2.1_y\tmain\n' > "$W/sel.tsv"
SEL="$W/sel.tsv"; T="$W/T"; JOBS=2
eval "$(sed -n '/^worker() {/,/^}/p' "$HW/scripts/fetch_screen_databases.sh")"; export -f worker
eval "$(grep -A1 '^tail -n +2 "\$SEL"' "$HW/scripts/fetch_screen_databases.sh")"
[ -s "$T/genomes/GCF_1.1.fa.gz" ] && [ -s "$T/genomes/GCF_2.1.fa.gz" ] || { echo "genome files missing: $(ls "$T/genomes")"; cat "$T/failed.txt" 2>/dev/null; exit 1; }
[ ! -s "$T/failed.txt" ] || { echo "failures recorded"; cat "$T/failed.txt"; exit 1; }
zcat "$T/genomes/GCF_1.1.fa.gz" | head -1 | grep -q '^>bacteria|GCF_1.1|seq1' || { echo "wrong sequence name"; exit 1; }
grep -q 'GCF_2.1_y_genomic.fna.gz' "$W/urls" || { echo "wrong URL"; cat "$W/urls"; exit 1; }
