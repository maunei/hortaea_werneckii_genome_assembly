#!/bin/bash
# Step 09: are the three runs of the procedure the same? Writes results/09_summary/replicate_check.tsv with, for each run, the checksum of the corrected reads
# (sorted, because the order of the reads written by a multithreaded program varies), of the raw assembly and of the polished assembly (one line per contig, sorted, because the order of the contigs
# in the file can vary), and the thread setting of the procedure; the last column is a checksum of the contig sequences alone (names and orientation ignored).
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
out="$RESULTS/09_summary/replicate_check.tsv"; mkdir -p "$(dirname "$out")"
printf "run\tthreads\tcorrected_reads\tcorrected_reads_md5_sorted\traw_assembly_md5\tpolished_assembly_md5\tpolished_assembly_md5_file_as_written\tpolished_assembly_sequences_md5\n" > "$out"
for r in r1 r2 r3; do
  th=$(grep -h "^RUN=$r " "$HW"/logs/hw_04_procedure_*.out | head -1 | sed 's/.*THREADS=//')
  CF="$WORK/asm/proc_${r}_raw/corrected.fasta"; RF="$WORK/asm/proc_${r}_raw/final.fasta"; PF="$WORK/asm/proc_$r/final.fasta"   # a file that does not exist gives "missing", not the checksum of an empty input
  if [ -s "$CF" ]; then n=$(grep -c '>' "$CF"); c=$(paste - - < "$CF" | sort | md5sum | cut -d' ' -f1); else n=missing; c=missing; fi
  lin() { awk '/^>/{if(s!="")print n"\t"s; n=$1; s=""; next}{s=s $0}END{print n"\t"s}' "$1" | sort | md5sum | cut -d' ' -f1; }
  if [ -s "$RF" ]; then a=$(lin "$RF"); else a=missing; fi
  if [ -s "$PF" ]; then p=$(lin "$PF"); pf=$(md5sum < "$PF" | cut -d' ' -f1); else p=missing; pf=missing; fi
  # checksum of the contig sequences alone: every contig as the smaller of its sequence and its reverse complement, sorted; the names of the contigs and their orientation are ignored (two contigs of equal length can swap names between runs)
  ps=missing; [ -s "$PF" ] && ps=$("$PY" - "$PF" <<'PYEOF'
import sys, hashlib
comp = str.maketrans('ACGTacgtN', 'TGCAtgcaN'); seqs = []; cur = []
for l in open(sys.argv[1]):
    if l[0] == '>':
        if cur: seqs.append(''.join(cur))
        cur = []
    else: cur.append(l.strip())
if cur: seqs.append(''.join(cur))
print(hashlib.md5('\n'.join(sorted(min(s, s.translate(comp)[::-1]) for s in seqs)).encode()).hexdigest())
PYEOF
)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "proc_$r" "$th" "$n" "$c" "$a" "$p" "$pf" "$ps" >> "$out"
done
cat "$out"
