"""Per-file metrics of PacBio RS II .bax.h5 files: ZMW productivity, read score, signal-to-noise, polymerase-read and subread lengths. Usage: eval_Q2_pacbio_metrics.py OUT.json FILE.bax.h5 ..."""
import sys, json, h5py, numpy as np
out = {}
def n50(x):
    x = np.sort(np.asarray(x))[::-1]; c = np.cumsum(x); return int(x[np.searchsorted(c, c[-1] / 2)])
for f in sys.argv[2:]:
    h = h5py.File(f, 'r'); b = h['PulseData/BaseCalls']; m = b['ZMWMetrics']
    prod = m['Productivity'][:]; rs = m['ReadScore'][:]; snr = m['HQRegionSNR'][:]; reg = h['PulseData/Regions'][:]
    hq = reg[reg[:, 1] == 2]; ins = reg[reg[:, 1] == 1]
    hql = (hq[:, 3] - hq[:, 2]).astype(int); sub = (ins[:, 3] - ins[:, 2]).astype(int)
    pr = prod == 1
    out[f.split('/')[-1]] = dict(zmws=int(len(prod)), productive_P1=int(pr.sum()), empty_P0=int((prod == 0).sum()), other_P2=int((prod == 2).sum()),
        readscore_mean_P1=float(rs[pr].mean()), frac_readscore_ge_0_80=float((rs[pr] >= 0.8).mean()), snr_mean_ACGT=[float(x) for x in snr[pr].mean(axis=0)],
        hq_polymerase_read_mean=float(hql[hql > 0].mean()), hq_polymerase_read_n50=n50(hql[hql > 0]), subreads=int(len(sub)), subread_mean=float(sub.mean()), subread_n50=n50(sub), hq_bases=int(hql.sum()))
json.dump(out, open(sys.argv[1], 'w'), indent=1); print(json.dumps({k: {a: v[a] for a in ('zmws', 'productive_P1', 'frac_readscore_ge_0_80', 'subread_n50')} for k, v in out.items()}))
