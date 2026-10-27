"""Reads a PAF of PacBio reads aligned to an assembly (minimap2 -c, standard input) and writes a compact table (standard output) with one line per
alignment record of at least MIN_BLOCK aligned bases: read, read length, read start, read end, strand, contig, contig length, start, end, mapping quality,
and the long gaps of the alignment (insertions I and deletions D of at least GAP_MIN bases, as 'type:position on the contig:length', comma-separated; '.' if none).
Usage: minimap2 ... | 07_compact_read_alignments.py [GAP_MIN=200] [MIN_BLOCK=500] | gzip > out.tsv.gz"""
import sys, re
gap_min = int(sys.argv[1]) if len(sys.argv) > 1 else 200
min_block = int(sys.argv[2]) if len(sys.argv) > 2 else 500
cig = re.compile(r'(\d+)([MIDNSHP=X])')
w = sys.stdout.write
w('read\tqlen\tqs\tqe\tstrand\tcontig\ttlen\tts\tte\tmapq\tgaps\n')
for line in sys.stdin:
    f = line.rstrip('\n').split('\t')
    if int(f[10]) < min_block: continue
    cg = None
    for t in f[12:]:
        if t.startswith('cg:Z:'): cg = t[5:]; break
    if cg is None: raise SystemExit('cigar missing: run minimap2 with -c')
    tpos = int(f[7]); gaps = []
    for n, op in cig.findall(cg):
        n = int(n)
        if op in 'M=XN': tpos += n
        elif op == 'D':
            if n >= gap_min: gaps.append('D:%d:%d' % (tpos, n))
            tpos += n
        elif op == 'I' and n >= gap_min: gaps.append('I:%d:%d' % (tpos, n))
    w('\t'.join([f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[11], ','.join(gaps) or '.']) + '\n')
