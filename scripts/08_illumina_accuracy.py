#!/usr/bin/env python3
"""Step 08, helper of jobs/08_illumina_accuracy.sbatch: three sub-commands.

depth-limits  window depth file (mosdepth, 1 kb windows) -> median window depth and the depth limits of callable positions
chunks        split the callable intervals into groups of whole contigs of similar size (parallel variant calling)
summarize     calls + callable intervals + mapping statistics -> differences.tsv, per_contig.tsv, windows_10kb.tsv,
              substitution_types.tsv, indel_lengths.tsv, summary.json
"""
import argparse, gzip, json, math, os, sys, collections
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from diff_common import read_fasta, trim_event, event_class, indel_context

WINDOW = 10000        # window of the arrangement along the contigs
NEAR = 1000           # distance for "another difference nearby"
NSIM = 200            # replicates of the uniform-scatter expectation
SEED = 1


def opener(p):
    return gzip.open(p, "rt") if p.endswith(".gz") else open(p)


# ---------------------------------------------------------------- depth-limits
def cmd_depth_limits(a):
    d = []
    with opener(a.regions) as fh:
        for line in fh:
            c, s, e, v = line.rstrip("\n").split("\t")[:4]
            if int(e) - int(s) == a.window:       # full windows only: partial windows at contig ends are left out
                d.append(float(v))
    if not d:
        sys.exit("no full window in " + a.regions)
    med = float(np.median(d))
    hi = int(math.floor(a.factor * med))
    out = dict(window=a.window, n_windows=len(d), median_window_depth=med, min_depth=a.min_depth,
               max_depth_factor=a.factor, max_depth=hi)
    json.dump(out, open(a.out, "w"), indent=1)
    if hi < a.min_depth:
        sys.exit(f"upper depth limit {hi} is below the lower limit {a.min_depth}; the reads do not cover the assembly deeply enough")
    print(hi)


# ---------------------------------------------------------------- chunks
def read_bed(p):
    iv = collections.OrderedDict()
    with opener(p) as fh:
        for line in fh:
            f = line.split("\t")
            iv.setdefault(f[0], []).append((int(f[1]), int(f[2])))
    return iv


def cmd_chunks(a):
    iv = read_bed(a.callable)
    size = {c: sum(e - s for s, e in v) for c, v in iv.items()}
    n = max(1, min(a.n, len(iv)))
    load, groups = [0] * n, [[] for _ in range(n)]
    for c in sorted(size, key=lambda k: -size[k]):       # largest first, always into the lightest group
        i = load.index(min(load)); groups[i].append(c); load[i] += size[c]
    k = 0
    for g in groups:
        if not g:
            continue
        with open(f"{a.prefix}{k:02d}.bed", "w") as w:
            for c in g:
                for s, e in iv[c]:
                    w.write(f"{c}\t{s}\t{e}\n")
        k += 1
    print(k)


# ---------------------------------------------------------------- summarize
def parse_flagstat(p):
    j = json.load(open(p))["QC-passed reads"]
    return j


def parse_samstats(p):
    sn = {}
    for line in open(p):
        if line.startswith("SN\t"):
            f = line.rstrip("\n").split("\t")
            sn[f[1].rstrip(":")] = float(f[2].split()[0]) if f[2].split() else float("nan")
    return sn


def pct(x, y):
    return 100.0 * x / y if y else float("nan")




def window_counts(cid, pos, elig_keys):
    """Counts per eligible 10 kb window (array aligned with elig_keys, sorted); differences in other windows are ignored."""
    wkey = cid.astype(np.int64) * 1_000_000 + (pos // WINDOW).astype(np.int64)
    idx = np.searchsorted(elig_keys, wkey)
    idx[idx >= len(elig_keys)] = 0
    ok = elig_keys[idx] == wkey
    return np.bincount(idx[ok], minlength=len(elig_keys))


def arrangement(cid, pos, elig_keys):
    n = len(cid)
    key = cid.astype(np.int64) * (1 << 32) + pos.astype(np.int64)
    key.sort()
    near = np.zeros(n, dtype=bool)
    if n > 1:
        d = np.diff(key)
        near[:-1] |= d <= NEAR
        near[1:] |= d <= NEAR
    wc = window_counts(cid, pos, elig_keys)
    mean = wc.mean() if len(wc) else float("nan")
    return dict(near_fraction=float(near.mean()) if n else float("nan"),
                window_mean=float(mean),
                window_dispersion=float(wc.var() / mean) if mean > 0 else float("nan"),
                window_zero_fraction=float((wc == 0).mean()) if len(wc) else float("nan"),
                window_max=int(wc.max()) if len(wc) else 0)


def cmd_summarize(a):
    rng = np.random.default_rng(SEED)
    seqs = read_fasta(a.fasta)
    names = [l.split("\t")[0] for l in open(a.fasta + ".fai")]
    length = {l.split("\t")[0]: int(l.split("\t")[1]) for l in open(a.fasta + ".fai")}
    cidx = {c: i for i, c in enumerate(names)}
    depth_lim = json.load(open(a.depth_limits))
    os.makedirs(a.outdir, exist_ok=True)

    # ---- callable intervals
    iv = read_bed(a.callable)
    callable_bp = {c: sum(e - s for s, e in iv.get(c, [])) for c in names}
    total_callable = sum(callable_bp.values())
    asm_bp = sum(length.values())
    iv_c, iv_s, iv_e = [], [], []
    for c in names:
        for s, e in iv.get(c, []):
            iv_c.append(cidx[c]); iv_s.append(s); iv_e.append(e)
    iv_c, iv_s, iv_e = map(np.array, (iv_c, iv_s, iv_e))
    iv_len = iv_e - iv_s
    iv_cum_end = np.cumsum(iv_len)
    iv_cum_start = iv_cum_end - iv_len
    contig_cum_start = {}      # first callable index of each contig, and its callable length
    for c in names:
        m = np.where(iv_c == cidx[c])[0]
        if len(m):
            contig_cum_start[c] = int(iv_cum_start[m[0]])

    # ---- raw calls -> differences
    min_depth, min_frac = a.min_depth, a.min_alt_fraction
    rows, partial = [], 0
    with open(a.calls) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            contig, pos1, ref, alts, qual, ad = f[0], int(f[1]), f[2], f[3].split(","), float(f[4]), f[5]
            adv = [int(x) for x in ad.split(",") if x != "."]
            if len(adv) != len(alts) + 1:
                continue
            dp = sum(adv)
            if dp < min_depth:
                continue
            nonref = dp - adv[0]
            frac = nonref / dp
            if frac < min_frac:
                partial += 1
                continue
            k = int(np.argmax(adv[1:]))             # dominant non-reference allele
            start0, refseq, altseq = trim_event(pos1, ref, alts[k])
            cls = event_class(refseq, altseq)
            length_ev = max(len(refseq), len(altseq)) if cls in ("ins", "del") else len(refseq)
            hp, run = (False, 0)
            if cls in ("ins", "del"):
                hp, run = indel_context(seqs[contig], start0, refseq, altseq)
            rows.append((contig, pos1, cls, ref, alts[k], length_ev, dp, adv[0], adv[1 + k], nonref, round(frac, 4), qual,
                         len(alts) > 1, ("yes" if hp else "no") if cls in ("ins", "del") else "NA", run if cls in ("ins", "del") else "NA",
                         start0, refseq, altseq))
    hdr = ["contig", "pos", "type", "ref_allele", "alt_allele", "length", "depth", "reads_ref", "reads_alt", "reads_nonref",
           "nonref_fraction", "qual", "multiallelic", "homopolymer", "homopolymer_run", "event_start0", "event_ref", "event_alt"]
    with open(os.path.join(a.outdir, "differences.tsv"), "w") as w:
        w.write("\t".join(hdr) + "\n")
        for r in rows:
            w.write("\t".join(map(str, r)) + "\n")
    types = collections.Counter(r[2] for r in rows)
    mb = total_callable / 1e6

    # ---- per contig
    per = {c: collections.Counter() for c in names}
    for r in rows:
        per[r[0]][r[2]] += 1
    mean_depth = {}
    if a.mosdepth_summary and os.path.exists(a.mosdepth_summary):
        for line in open(a.mosdepth_summary):
            f = line.rstrip("\n").split("\t")
            if f[0] in length:
                mean_depth[f[0]] = float(f[3])
    with open(os.path.join(a.outdir, "per_contig.tsv"), "w") as w:
        w.write("contig\tlength\tcallable_bp\tcallable_fraction\tmean_depth_mapq30\tn_snv\tn_ins\tn_del\tn_complex\tn_total\tdifferences_per_mb_callable\n")
        for c in names:
            p = per[c]; n = sum(p.values()); cb = callable_bp[c]
            dens = f"{n / (cb / 1e6):.3f}" if cb >= 1000 else "NA"
            w.write(f"{c}\t{length[c]}\t{cb}\t{cb / length[c]:.4f}\t{mean_depth.get(c, float('nan')):.2f}\t{p['snv']}\t{p['ins']}\t{p['del']}\t{p['complex']}\t{n}\t{dens}\n")

    # ---- windows of 10 kb: counts and eligibility (full window, at least half callable)
    cb_win = collections.defaultdict(int)
    for c in names:
        for s, e in iv.get(c, []):
            for wi in range(s // WINDOW, (e - 1) // WINDOW + 1):
                lo, hi = max(s, wi * WINDOW), min(e, (wi + 1) * WINDOW)
                cb_win[(cidx[c], wi)] += hi - lo
    wcount = collections.defaultdict(lambda: [0, 0])
    for r in rows:
        wcount[(cidx[r[0]], (r[1] - 1) // WINDOW)][0 if r[2] == "snv" else 1] += 1
    elig = []
    with open(os.path.join(a.outdir, "windows_10kb.tsv"), "w") as w:
        w.write("contig\tstart0\tend\tcallable_bp\tn_snv\tn_other\teligible\n")
        for c in names:
            for wi in range((length[c] + WINDOW - 1) // WINDOW):
                s, e = wi * WINDOW, min((wi + 1) * WINDOW, length[c])
                cb = cb_win.get((cidx[c], wi), 0)
                ok = (e - s == WINDOW) and cb >= WINDOW // 2
                if ok:
                    elig.append(cidx[c] * 1_000_000 + wi)
                n1, n2 = wcount.get((cidx[c], wi), [0, 0])
                if cb or n1 or n2:
                    w.write(f"{c}\t{s}\t{e}\t{cb}\t{n1}\t{n2}\t{int(ok)}\n")
    elig_keys = np.array(sorted(elig), dtype=np.int64)

    # ---- arrangement: observed and two uniform-scatter expectations
    cid = np.array([cidx[r[0]] for r in rows], dtype=np.int64)
    pos0 = np.array([r[1] - 1 for r in rows], dtype=np.int64)
    n = len(rows)
    obs = arrangement(cid, pos0, elig_keys) if n else {}
    arr = {"observed": obs}
    if n >= 2 and len(iv_c):
        def sample_genome():
            idx = rng.integers(0, total_callable, n)
            j = np.searchsorted(iv_cum_end, idx, side="right")
            return iv_c[j], iv_s[j] + (idx - iv_cum_start[j])
        cnt_c = collections.Counter(cid.tolist())
        cs_c = np.array([c for c in cnt_c for _ in range(cnt_c[c])], dtype=np.int64)
        base = np.array([contig_cum_start.get(names[c], 0) for c in cs_c], dtype=np.int64)
        clen = np.array([max(callable_bp[names[c]], 1) for c in cs_c], dtype=np.int64)
        def sample_contig():
            idx = base + np.minimum((rng.random(len(cs_c)) * clen).astype(np.int64), clen - 1)
            j = np.searchsorted(iv_cum_end, idx, side="right")
            return iv_c[j], iv_s[j] + (idx - iv_cum_start[j])
        for label, fn in (("expected_uniform_genome", sample_genome), ("expected_uniform_within_contigs", sample_contig)):
            reps = [arrangement(*fn(), elig_keys) for _ in range(NSIM)]
            e = {}
            for k in obs:
                v = np.array([r[k] for r in reps], dtype=float)
                e[k] = dict(mean=float(np.nanmean(v)), sd=float(np.nanstd(v)), p_ge_observed=float((np.sum(v >= obs[k]) + 1) / (len(v) + 1)))
            e["replicates"] = NSIM
            arr[label] = e
    # contigs of highest density
    ranked = [(c, sum(per[c].values()) / (callable_bp[c] / 1e6)) for c in names if callable_bp[c] >= a.min_callable_rank]
    ranked.sort(key=lambda x: -x[1])
    genome_density = n / mb if mb else float("nan")
    top = [dict(contig=c, length=length[c], callable_bp=callable_bp[c], n_differences=sum(per[c].values()),
                differences_per_mb=round(d, 3), ratio_to_assembly=round(d / genome_density, 2) if genome_density else None)
           for c, d in ranked[:10]]
    dens_all = np.array([d for _, d in ranked]) if ranked else np.array([])

    # ---- substitution types and indel lengths
    comp = {"A": "T", "C": "G", "G": "C", "T": "A"}
    sub = collections.Counter(f"{r[16]}>{r[17]}" for r in rows if r[2] == "snv")
    with open(os.path.join(a.outdir, "substitution_types.tsv"), "w") as w:
        w.write("assembly_base\tread_base\tcount\n")
        for x in "ACGT":
            for y in "ACGT":
                if x != y:
                    w.write(f"{x}\t{y}\t{sub[f'{x}>{y}']}\n")
    six = collections.Counter()
    for k, v in sub.items():
        x, y = k.split(">")
        if x in "AG":
            x, y = comp[x], comp[y]
        six[f"{x}>{y}"] += v
    ts = six["C>T"] + six["T>C"]
    tv = sum(six.values()) - ts
    ilen = collections.defaultdict(lambda: [0, 0])
    for r in rows:
        if r[2] in ("ins", "del"):
            ilen[(r[2], r[5])][0] += 1
            ilen[(r[2], r[5])][1] += r[13] == "yes"
    with open(os.path.join(a.outdir, "indel_lengths.tsv"), "w") as w:
        w.write("type\tlength\tcount\tin_homopolymer\n")
        for (t, l), (c, h) in sorted(ilen.items()):
            w.write(f"{t}\t{l}\t{c}\t{h}\n")
    def indel_block(t):
        L = [(l, c, h) for (tt, l), (c, h) in ilen.items() if tt == t]
        tot = sum(c for _, c, _ in L)
        hp = sum(h for _, _, h in L)
        one = sum(c for l, c, _ in L if l == 1)
        one_hp = sum(h for l, _, h in L if l == 1)
        return dict(count=tot, in_homopolymer=hp, fraction_in_homopolymer=hp / tot if tot else None,
                    length_1=one, length_1_in_homopolymer=one_hp, length_2=sum(c for l, c, _ in L if l == 2),
                    length_3_to_5=sum(c for l, c, _ in L if 3 <= l <= 5), length_over_5=sum(c for l, c, _ in L if l > 5),
                    longest=max([l for l, _, _ in L], default=0))

    # ---- mapping statistics
    fs = parse_flagstat(a.flagstat)
    st = parse_samstats(a.samstats)
    mq = [int(x) for x in open(a.mapq30).read().split()]      # primary reads, primary mapped reads with mapping quality >= 30
    mapping = dict(
        reads_primary=int(fs["primary"]), read_pairs=int(fs["primary"]) // 2,
        primary_mapped=int(fs["primary mapped"]), percent_mapped=pct(fs["primary mapped"], fs["primary"]),
        properly_paired=int(fs["properly paired"]), percent_properly_paired=pct(fs["properly paired"], fs["paired in sequencing"]),
        percent_mapq_ge_30=pct(mq[1], mq[0]),
        percent_mate_on_other_contig=pct(fs["with mate mapped to a different chr"], fs["with itself and mate mapped"]),
        bases_mapped_cigar=int(st.get("bases mapped (cigar)", 0)), mismatches_nm=int(st.get("mismatches", 0)),
        mismatch_rate_per_base=st.get("error rate", float("nan")),
        average_read_length=st.get("average length"))
    nph = [r for r in rows if r[2] in ("ins", "del")]
    summary = dict(
        assembly=a.asm, thresholds=dict(min_mapq=a.min_mapq, min_base_quality=a.min_baseq, min_depth=min_depth,
                                        max_depth=depth_lim["max_depth"], min_nonref_fraction=min_frac, min_qual=a.min_qual,
                                        homopolymer_min_run=3),
        mapping=mapping,
        callable=dict(assembly_bp=asm_bp, callable_bp=total_callable, callable_fraction=total_callable / asm_bp,
                      median_window_depth=depth_lim["median_window_depth"], max_depth=depth_lim["max_depth"]),
        differences=dict(total=n, snv=types["snv"], insertions=types["ins"], deletions=types["del"], complex=types["complex"],
                         per_mb_callable=dict(total=n / mb if mb else None, snv=types["snv"] / mb if mb else None,
                                              insertions_and_deletions=(types["ins"] + types["del"]) / mb if mb else None,
                                              insertions=types["ins"] / mb if mb else None, deletions=types["del"] / mb if mb else None,
                                              complex=types["complex"] / mb if mb else None),
                         multiallelic_sites=int(sum(1 for r in rows if r[12])),
                         partial_sites_below_threshold=partial),
        substitution_types=dict(twelve=dict(sub), six_pyrimidine_reference=dict(six), transitions=ts, transversions=tv,
                                transition_transversion_ratio=ts / tv if tv else None),
        indels=dict(insertions=indel_block("ins"), deletions=indel_block("del")),
        genotype_check=dict(percent_mapped=mapping["percent_mapped"], percent_properly_paired=mapping["percent_properly_paired"],
                            mismatch_rate_per_base=mapping["mismatch_rate_per_base"], differences_per_mb_callable=genome_density,
                            arrangement=arr, windows_eligible=int(len(elig_keys)), window_size=WINDOW, near_distance=NEAR,
                            contigs_ranked=len(ranked), contigs_density_over_5x_assembly=int(np.sum(dens_all > 5 * genome_density)) if len(dens_all) else 0,
                            min_callable_bp_for_ranking=a.min_callable_rank, top_contigs_by_density=top))
    json.dump(summary, open(os.path.join(a.outdir, "summary.json"), "w"), indent=1)
    print(json.dumps({k: summary[k] for k in ("differences",)}, indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("depth-limits")
    p.add_argument("--regions", required=True); p.add_argument("--out", required=True)
    p.add_argument("--window", type=int, default=1000); p.add_argument("--min-depth", type=int, default=10)
    p.add_argument("--factor", type=float, default=2.0)
    p.set_defaults(fn=cmd_depth_limits)
    p = sp.add_parser("chunks")
    p.add_argument("--callable", required=True); p.add_argument("--prefix", required=True); p.add_argument("--n", type=int, default=8)
    p.set_defaults(fn=cmd_chunks)
    p = sp.add_parser("summarize")
    p.add_argument("--asm", required=True); p.add_argument("--fasta", required=True, help="indexed FASTA used for mapping (.fai next to it)")
    p.add_argument("--calls", required=True); p.add_argument("--callable", required=True)
    p.add_argument("--flagstat", required=True); p.add_argument("--samstats", required=True); p.add_argument("--mapq30", required=True)
    p.add_argument("--depth-limits", required=True); p.add_argument("--mosdepth-summary")
    p.add_argument("--outdir", required=True)
    p.add_argument("--min-depth", type=int, default=10); p.add_argument("--min-alt-fraction", type=float, default=0.9)
    p.add_argument("--min-mapq", type=int, default=30); p.add_argument("--min-baseq", type=int, default=25)
    p.add_argument("--min-qual", type=float, default=30)
    p.add_argument("--min-callable-rank", type=int, default=100000)
    p.set_defaults(fn=cmd_summarize)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
