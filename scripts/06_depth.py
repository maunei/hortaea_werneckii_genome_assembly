"""Step 06, line 4: depth of the PacBio reads in windows of 1 kb (from the mosdepth table).
Usage: 06_depth.py DEPTH.regions.bed.gz OUT_PREFIX
The median is the median window depth weighted by window length (a window shorter than 1 kb at the end of a contig counts with its own length).
frac_0_5_to_1_5 : fraction of the bases that lie in windows with depth from 0.5 to 1.5 times the median (0.5 <= depth/median < 1.5).
The windows that contain the first or the last base of a contig are the terminal windows; the same fraction without them is given as frac_0_5_to_1_5_inner,
because reads can reach a contig end from one side only and depth falls off there by construction.
Writes OUT_PREFIX.tsv (the classes) and OUT_PREFIX.json.
"""
import sys, gzip, json
import numpy as np
bed, prefix = sys.argv[1], sys.argv[2]
ctg, w, d = [], [], []
with gzip.open(bed, 'rt') as f:
    for l in f:
        c, s, e, x = l.split(); ctg.append(c); w.append(int(e) - int(s)); d.append(float(x))
w = np.array(w); d = np.array(d); ctg = np.array(ctg)
assert len(w) > 0
first = np.r_[True, ctg[1:] != ctg[:-1]]; last = np.r_[ctg[1:] != ctg[:-1], True]
inner = ~(first | last)
def wmedian(dep, wt):
    o = np.argsort(dep); cs = np.cumsum(wt[o]); return float(dep[o][np.searchsorted(cs, cs[-1] / 2)])
med = wmedian(d, w)
r = d / med if med > 0 else np.zeros_like(d)
def frac(lo, hi, m=None):
    m = np.ones(len(w), bool) if m is None else m
    t = w[m].sum()
    return float(w[m & (r >= lo) & (r < hi)].sum() / t) if t else None
classes = [('below_0_25', 0, 0.25), ('0_25_to_0_5', 0.25, 0.5), ('0_5_to_1_5', 0.5, 1.5), ('1_5_to_2_5', 1.5, 2.5), ('at_least_2_5', 2.5, 1e18)]
res = dict(median_depth=med, windows=int(len(w)), bases=int(w.sum()), windows_terminal=int((~inner).sum()), mean_depth=float((d * w).sum() / w.sum()))
for k, lo, hi in classes: res['frac_' + k] = frac(lo, hi)
res['frac_0_5_to_1_5_inner'] = frac(0.5, 1.5, inner)
with open(prefix + '.tsv', 'w') as o:
    o.write('depth_class_times_median\tfraction_of_bases\tfraction_of_bases_inner_windows\n')
    for k, lo, hi in classes: o.write(f'{k}\t{frac(lo, hi):.6f}\t' + (f'{frac(lo, hi, inner):.6f}' if inner.any() else 'NA') + '\n')
json.dump(res, open(prefix + '.json', 'w'), indent=1)
