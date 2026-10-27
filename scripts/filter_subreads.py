"""Read filter of step 02a: keeps the subreads whose ZMW (zero-mode waveguide, the sequencing well) is productive with read score >= 0.80 and that are >= 500 bases (the default filter of the original protocol, applied here). Usage: filter_subreads.py IN.fastq OUT.fastq BAX..."""
import sys, h5py, re
keep = set()
for f in sys.argv[3:]:
    h = h5py.File(f, 'r'); b = h['PulseData/BaseCalls']; hn = b['ZMW/HoleNumber'][:]; m = b['ZMWMetrics']
    ok = (m['Productivity'][:] == 1) & (m['ReadScore'][:] >= 0.80); keep.update(int(x) for x in hn[ok])
n = k = 0
with open(sys.argv[1]) as fi, open(sys.argv[2], 'w') as fo:
    while True:
        h = fi.readline()
        if not h: break
        s = fi.readline(); p = fi.readline(); q = fi.readline(); n += 1
        hole = int(h.split('/')[1]); a, b_ = re.search(r'/(\d+)_(\d+)', h).groups()
        if hole in keep and len(s.strip()) >= 500: fo.write(h + s + p + q); k += 1
print(n, 'subreads', k, 'kept')
