#!/usr/bin/env python3
"""Differences between the Illumina reads and two assemblies that are at the same place in both (step 08).

Both assemblies are built from the same PacBio reads, so a difference found in both cannot come from the assembly
procedure. Method: each difference of an assembly is described by its context, that is the 20 assembly bases on each side
of the site (41 bases for a single-base difference), the assembly sequence at the site and the sequence the reads carry.
The description is turned into its canonical orientation (the smaller of the forward and the reverse-complement
description), and two differences are the same when the descriptions are identical. For insertions and deletions the same
is done with 20 bases on each side of the inserted or deleted sequence (no bases for the site itself), with the indel
written in its left-aligned form in both assemblies.

Usage: shared_differences.py --diff-a A/differences.tsv --fasta-a A.fa --name-a A --diff-b B/differences.tsv --fasta-b B.fa --name-b B --outdir DIR
"""
import argparse, collections, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from diff_common import read_fasta, trim_event, event_class, event_key


def load(diff, fasta, flank):
    """-> list of (contig, pos, type, key or None) for one assembly."""
    seqs = read_fasta(fasta)
    out = []
    with open(diff) as fh:
        hdr = fh.readline().rstrip("\n").split("\t")
        ix = {h: i for i, h in enumerate(hdr)}
        for line in fh:
            f = line.rstrip("\n").split("\t")
            c = f[ix["contig"]]
            start0, ref, alt = trim_event(int(f[ix["pos"]]), f[ix["ref_allele"]], f[ix["alt_allele"]])
            cls = event_class(ref, alt)
            key = event_key(seqs[c], start0, ref, alt, flank) if c in seqs else None
            out.append((c, int(f[ix["pos"]]), cls, key, f[ix["ref_allele"]], f[ix["alt_allele"]]))
    return out


def callable_mb(diff_path):
    p = os.path.join(os.path.dirname(os.path.abspath(diff_path)), "summary.json")
    if os.path.exists(p):
        return json.load(open(p))["callable"]["callable_bp"] / 1e6
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--diff-a", required=True); ap.add_argument("--fasta-a", required=True); ap.add_argument("--name-a", required=True)
    ap.add_argument("--diff-b", required=True); ap.add_argument("--fasta-b", required=True); ap.add_argument("--name-b", required=True)
    ap.add_argument("--flank", type=int, default=20, help="bases on each side (20 gives the 41-base window of a single-base difference)")
    ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    side = {a.name_a: load(a.diff_a, a.fasta_a, a.flank), a.name_b: load(a.diff_b, a.fasta_b, a.flank)}
    mb = {a.name_a: callable_mb(a.diff_a), a.name_b: callable_mb(a.diff_b)}
    other = {a.name_a: a.name_b, a.name_b: a.name_a}
    keys = {n: collections.Counter(r[3] for r in rows if r[3] is not None) for n, rows in side.items()}
    summary = dict(window_description=f"{a.flank} assembly bases on each side of the site; canonical orientation; exact match",
                   assemblies={})
    for n, rows in side.items():
        o = other[n]
        classes = ("snv", "ins", "del", "complex")
        cnt = {k: collections.Counter() for k in ("total", "untestable", "shared", "specific", "ambiguous_key")}
        with open(os.path.join(a.outdir, f"{n}_status.tsv"), "w") as w:
            w.write("contig\tpos\ttype\tref_allele\talt_allele\tstatus\tkey_multiplicity_here\tkey_multiplicity_other\n")
            for c, pos, cls, key, ref, alt in rows:
                cnt["total"][cls] += 1
                if key is None:
                    st, m1, m2 = "untestable", 0, 0       # window leaves the contig or contains an N
                    cnt["untestable"][cls] += 1
                else:
                    m1, m2 = keys[n][key], keys[o][key]
                    st = "shared" if m2 > 0 else "specific"
                    cnt[st][cls] += 1
                    if m1 > 1 or m2 > 1:
                        cnt["ambiguous_key"][cls] += 1
                w.write(f"{c}\t{pos}\t{cls}\t{ref}\t{alt}\t{st}\t{m1}\t{m2}\n")
        d = {}
        for k, c in cnt.items():
            d[k] = dict({x: c[x] for x in classes}, all=sum(c.values()))
        if mb[n]:
            d["callable_mb"] = mb[n]
            d["specific_per_mb_callable"] = {x: cnt["specific"][x] / mb[n] for x in classes}
            d["specific_per_mb_callable"]["all"] = sum(cnt["specific"].values()) / mb[n]
            d["shared_per_mb_callable"] = sum(cnt["shared"].values()) / mb[n]
        summary["assemblies"][n] = d
    summary["distinct_shared_descriptions"] = sum(1 for k in keys[a.name_a] if k in keys[a.name_b])
    json.dump(summary, open(os.path.join(a.outdir, "summary.json"), "w"), indent=1)
    with open(os.path.join(a.outdir, "counts.tsv"), "w") as w:
        w.write("assembly\ttype\ttotal\tshared\tspecific\tuntestable\n")
        for n in side:
            d = summary["assemblies"][n]
            for x in ("snv", "ins", "del", "complex", "all"):
                w.write(f"{n}\t{x}\t{d['total'][x]}\t{d['shared'][x]}\t{d['specific'][x]}\t{d['untestable'][x]}\n")
    print(json.dumps({n: {k: summary['assemblies'][n][k]['all'] for k in ('total', 'shared', 'specific', 'untestable')} for n in side}))


if __name__ == "__main__":
    main()
