#!/usr/bin/env python3
"""Summarise the self-test: per kind of control read (name between the bars of spike|KIND|n) and for the real reads, the class counts."""
import sys, os, gzip, collections
d = sys.argv[1]
rows = collections.defaultdict(collections.Counter); fr = collections.defaultdict(list)
with gzip.open(os.path.join(d, "selftest_per_read.tsv.gz"), "rt") as fh:
    h = next(fh).rstrip("\n").split("\t"); ix = {k: i for i, k in enumerate(h)}
    for l in fh:
        p = l.rstrip("\n").split("\t")
        k = p[0].split("|")[1] if p[0].startswith("spike|") else "real_reads_sample"
        rows[k][p[ix["class"]]] += 1
        fr[k].append((float(p[ix["frac_contaminant_any"]]), float(p[ix["frac_fungi"]])))
classes = ["excluded", "contaminant_majority_but_fungal_match_kept", "contaminant_minor_kept", "fungal_match_only_kept", "no_match_kept"]
with open(os.path.join(d, "selftest_sensitivity.tsv"), "w") as o:
    o.write("kind\tn_reads\t" + "\t".join(classes) + "\tfraction_excluded\tmedian_frac_contaminant\tmedian_frac_fungi\n")
    for k in sorted(rows, key=lambda x: (x == "real_reads_sample", x)):
        n = sum(rows[k].values()); a = sorted(x[0] for x in fr[k]); b = sorted(x[1] for x in fr[k])
        o.write(f"{k}\t{n}\t" + "\t".join(str(rows[k][c]) for c in classes) + f"\t{rows[k]['excluded'] / n:.3f}\t{a[n // 2]:.3f}\t{b[n // 2]:.3f}\n")
print(open(os.path.join(d, "selftest_sensitivity.tsv")).read())
