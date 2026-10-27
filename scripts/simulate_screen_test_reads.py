#!/usr/bin/env python3
"""Make test reads for the contaminant screen: error-containing reads drawn from known sequences (positive controls).

Reads imitate the error profile of PacBio RS II (P4/C2) subreads: about 14 % errors in total (insertions 55 %, deletions 28 %,
substitutions 17 % of the errors). A template can be diverged first (substitutions at a given rate) to imitate a relative of the
sequence that is not in the database, which measures how sensitivity falls with divergence.
Spec per source: --src NAME FASTA[.gz] N DIVERGENCE [SEQID_PREFIX]   (several allowed; SEQID_PREFIX limits to sequences whose name starts with it)
Chimeras: --chimera NAME FASTA_A DIV_A FASTA_B DIV_B N BASES_A BASES_B  (read = part of A followed by part of B)
Output: FASTQ (constant quality) with read names  spike|NAME|index.
"""
import argparse, gzip, random
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--src", nargs=5, action="append", default=[], metavar=("NAME", "FASTA", "N", "DIV", "PREFIX"))
ap.add_argument("--chimera", nargs=8, action="append", default=[])
ap.add_argument("--out", required=True)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--err", type=float, default=0.14)
a = ap.parse_args()
rng = np.random.default_rng(a.seed); random.seed(a.seed)
B = np.frombuffer(b"ACGT", dtype=np.uint8)
RC = bytes.maketrans(b"ACGT", b"TGCA")

def load(path, prefix):
    op = gzip.open if path.endswith(".gz") else open
    seqs, name, buf = {}, None, []
    with op(path, "rt") as fh:
        for l in fh:
            if l[0] == ">":
                if name: seqs[name] = "".join(buf)
                name = l[1:].split()[0]; buf = []
                if prefix != "all" and not name.split("|")[-1].startswith(prefix): name = None
            elif name:
                buf.append(l.strip().upper())
    if name: seqs[name] = "".join(buf)
    seqs = {k: v for k, v in seqs.items() if len(v) > 20000 and set(v[:5000]) <= set("ACGT")}
    return seqs

def diverge(arr, d):
    if d <= 0: return arr
    arr = arr.copy(); m = rng.random(arr.size) < d
    arr[m] = B[(np.searchsorted(B, arr[m]) + rng.integers(1, 4, m.sum())) % 4]
    return arr

def errors(arr):
    n = arr.size; u = rng.random(n); e = a.err
    ps, pd_, pi = 0.17 * e, 0.28 * e, 0.55 * e
    out = arr.copy(); sub = u < ps
    out[sub] = B[(np.searchsorted(B, out[sub]) + rng.integers(1, 4, sub.sum())) % 4]
    keep = ~((u >= ps) & (u < ps + pd_)); out = out[keep]
    ins = rng.random(out.size) < pi
    pos = np.nonzero(ins)[0]
    out = np.insert(out, pos + 1, B[rng.integers(0, 4, pos.size)])
    return out

def length():
    return int(min(max(rng.lognormal(np.log(4000), 0.5), 1000), 15000))

def draw(seq, L):
    if len(seq) <= L: L = len(seq)
    s = int(rng.integers(0, len(seq) - L + 1))
    return seq[s:s + L]

def write(fh, name, i, arr):
    s = arr.tobytes().decode()
    if rng.random() < 0.5: s = s.translate(RC)[::-1]
    fh.write(f"@spike|{name}|{i}\n{s}\n+\n{'+' * len(s)}\n")

with open(a.out, "w") as fh:
    for name, path, n, div, prefix in a.src:
        seqs = load(path, prefix); keys = list(seqs); w = np.array([len(seqs[k]) for k in keys], float); w /= w.sum()
        if not keys: raise SystemExit(f"no sequence of {path} usable")
        for i in range(int(n)):
            k = keys[rng.choice(len(keys), p=w)]
            t = np.frombuffer(draw(seqs[k], length()).encode(), dtype=np.uint8)
            write(fh, name, i, errors(diverge(t, float(div))))
    for name, pa, da, pb, db, n, la, lb in a.chimera:
        sa, sb = load(pa, "all"), load(pb, "all"); ka, kb = list(sa), list(sb)
        for i in range(int(n)):
            ta = np.frombuffer(draw(sa[random.choice(ka)], int(la)).encode(), dtype=np.uint8)
            tb = np.frombuffer(draw(sb[random.choice(kb)], int(lb)).encode(), dtype=np.uint8)
            write(fh, name, i, np.concatenate([errors(diverge(ta, float(da))), errors(diverge(tb, float(db)))]))
