"""Step 06, line 2: summary of the STAR alignment of the RNA-seq read pairs to one assembly.
Usage: 06_star_summary.py STAR_PREFIX_Log.final.out STAR_PREFIX_SJ.out.tab OUT_PREFIX
Classes of read pairs (fractions of the input pairs): unique (aligned to one place), multiple (aligned to 2 to 20 places), too_many (aligned to more than 20 places),
unmapped (too short, too many mismatches, other). STAR counts these classes by the pairs it reads; the four fractions add up to 1.
Splice junctions: canonical = motif GT/AG, GC/AG or AT/AC (motif codes 1 to 6 of the STAR table), non-canonical = code 0; junction reads = uniquely mapped reads crossing the junction.
"""
import sys, re, json
log, sj, prefix = sys.argv[1:4]
t = open(log).read()
def g(key):
    m = re.search(re.escape(key) + r'\s*\|\s*([\d.]+)', t)
    assert m, 'missing in Log.final.out: ' + key
    return float(m.group(1))
n = int(g('Number of input reads'))
uni = int(g('Uniquely mapped reads number')); mul = int(g('Number of reads mapped to multiple loci')); many = int(g('Number of reads mapped to too many loci'))
unm = n - uni - mul - many
can = non = njunc = 0
for l in open(sj):
    x = l.split(); njunc += 1; u = int(x[6])
    if x[4] == '0': non += u
    else: can += u
res = dict(input_pairs=n, unique_pairs=uni, multiple_pairs=mul, too_many_pairs=many, unmapped_pairs=unm,
           frac_unique=uni / n, frac_multiple=mul / n, frac_too_many=many / n, frac_unmapped=unm / n,
           mismatch_rate_percent=g('Mismatch rate per base, %'), deletion_rate_percent=g('Deletion rate per base') if 'Deletion rate per base' in t else None,
           insertion_rate_percent=g('Insertion rate per base') if 'Insertion rate per base' in t else None,
           average_input_read_length=g('Average input read length'), average_mapped_length=g('Average mapped length'),
           splice_junctions_detected=njunc, junction_reads_canonical=can, junction_reads_noncanonical=non,
           frac_junction_reads_canonical=can / (can + non) if can + non else None)
with open(prefix + '.tsv', 'w') as o:
    o.write('measure\tvalue\n')
    for k, v in res.items(): o.write(f'{k}\t{v}\n')
json.dump(res, open(prefix + '.json', 'w'), indent=1)
