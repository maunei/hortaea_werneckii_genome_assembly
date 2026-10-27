#!/usr/bin/env python3
"""Apply the exclusion criterion of the contaminant screen to filtered alignments of reads (or contigs).

Input : one or more PAF files (gzip allowed) with the columns written by screen_reads.sh
        (query name, query length, query start, query end, target name, residue matches, alignment length, mapping quality),
        a table of the sequences screened (name, length) and the database manifest (key -> organism).
        Target names have the form GROUP|KEY|original_id; GROUP is bacteria, archaea, virus, human, vector or fungi.
Output: per-sequence table, counts by class and group, list of excluded names, the criterion in json.

Criterion (fixed in the plan): a sequence is EXCLUDED only if the union of its aligned segments to contaminant
sequences (bacteria, archaea, virus, human, vector) covers at least MIN_CONTAM_FRAC (default 0.5, "most") of its length
AND it has no alignment to a fungal sequence (after the same alignment filter). Every other sequence is kept.
"""
import argparse, collections, gzip, json, sys

ap = argparse.ArgumentParser()
ap.add_argument("--paf", nargs="+", required=True)
ap.add_argument("--lengths", required=True, help="tsv: name<TAB>length for every sequence screened")
ap.add_argument("--manifest", required=True)
ap.add_argument("--outdir", required=True)
ap.add_argument("--label", required=True)
ap.add_argument("--min-contam-frac", type=float, default=0.5)
ap.add_argument("--min-aln-len", type=int, default=300, help="alignment length (bases) below which an alignment is ignored")
ap.add_argument("--min-identity", type=float, default=0.65, help="fungal alignments: residue matches / alignment length below which an alignment is ignored")
ap.add_argument("--min-identity-contaminant", type=float, default=0.70, help="same for alignments to contaminants (stronger evidence is asked before a read can be excluded)")
ap.add_argument("--kind", default="read", choices=["read", "contig"])
a = ap.parse_args()

CONT = ["bacteria", "archaea", "virus", "human", "vector"]
GROUPS = CONT + ["fungi"]

org = {}
with open(a.manifest) as fh:
    next(fh)
    for line in fh:
        p = line.rstrip("\n").split("\t")
        if len(p) >= 4:
            org[(p[0], p[1])] = p[3]

lengths = {}
order = []
with open(a.lengths) as fh:
    for line in fh:
        n, l = line.rstrip("\n").split("\t")[:2]
        lengths[n] = int(l); order.append(n)

iv = collections.defaultdict(lambda: collections.defaultdict(list))   # seq -> group -> [(s, e)]
tb = collections.defaultdict(lambda: collections.defaultdict(int))    # seq -> (group,key) -> aligned bases
nal = 0
for f in a.paf:
    op = gzip.open if f.endswith(".gz") else open
    with op(f, "rt") as fh:
        for line in fh:
            p = line.split("\t")
            q, ql, qs, qe, t, m, bl = p[0], int(p[1]), int(p[2]), int(p[3]), p[4], int(p[5]), int(p[6])
            g, key = t.split("|", 2)[:2]
            if bl < a.min_aln_len or m / bl < (a.min_identity if g == "fungi" else a.min_identity_contaminant):
                continue
            iv[q][g].append((qs, qe)); tb[q][(g, key)] += qe - qs; nal += 1

def union(lst):
    lst.sort(); tot = 0; cs, ce = lst[0]
    for s, e in lst[1:]:
        if s > ce:
            tot += ce - cs; cs, ce = s, e
        else:
            ce = max(ce, e)
    return tot + ce - cs

def union_multi(groups_iv):
    allv = [x for g in groups_iv for x in groups_iv[g]]
    return union(allv) if allv else 0

rows = []
counts = collections.Counter()
excl = []
for n in order:
    L = lengths[n]
    d = iv.get(n, {})
    fr = {g: (union(d[g]) / L if g in d and L > 0 else 0.0) for g in GROUPS}
    contam_any = union_multi({g: d[g] for g in CONT if g in d}) / L if L > 0 else 0.0
    fungal = fr["fungi"] > 0
    # contaminant group with the largest covered fraction; within it the target with most aligned bases
    bestg = max(CONT, key=lambda g: fr[g]) if contam_any > 0 else ""
    topc = ("", "")
    if bestg:
        cands = [(v, k) for k, v in tb[n].items() if k[0] == bestg]
        topc = max(cands)[1]
    if contam_any >= a.min_contam_frac and not fungal:
        cls = "excluded"
    elif contam_any >= a.min_contam_frac and fungal:
        cls = "contaminant_majority_but_fungal_match_kept"
    elif contam_any > 0:
        cls = "contaminant_minor_kept"
    elif fungal:
        cls = "fungal_match_only_kept"
    else:
        cls = "no_match_kept"
    if cls == "excluded":
        excl.append(n)
    counts[(cls, bestg if cls in ("excluded", "contaminant_majority_but_fungal_match_kept", "contaminant_minor_kept") else "")] += 1
    rows.append([n, L] + [f"{fr[g]:.4f}" for g in GROUPS] + [f"{contam_any:.4f}", bestg, topc[1], org.get(topc, ""), cls])

import os
os.makedirs(a.outdir, exist_ok=True)
hdr = [a.kind, "length"] + [f"frac_{g}" for g in GROUPS] + ["frac_contaminant_any", "best_contaminant_group", "best_contaminant_key", "best_contaminant_organism", "class"]
with gzip.open(os.path.join(a.outdir, f"{a.label}_per_{a.kind}.tsv.gz"), "wt") as o:
    o.write("\t".join(hdr) + "\n")
    for r in rows:
        o.write("\t".join(map(str, r)) + "\n")
with open(os.path.join(a.outdir, f"{a.label}_excluded_{a.kind}s.txt"), "w") as o:
    for n in excl:
        o.write(n + "\n")
with open(os.path.join(a.outdir, f"{a.label}_counts.tsv"), "w") as o:
    o.write("set\tclass\tcontaminant_group\tn_" + a.kind + "s\tbases\n")
    bases = collections.Counter()
    for r in rows:
        grp = r[-4] if r[-1] in ("excluded", "contaminant_majority_but_fungal_match_kept", "contaminant_minor_kept") else ""
        bases[(r[-1], grp)] += r[1]
    for (cls, g), c in sorted(counts.items()):
        o.write(f"{a.label}\t{cls}\t{g}\t{c}\t{bases[(cls, g)]}\n")
    o.write(f"{a.label}\tTOTAL\t\t{len(order)}\t{sum(lengths.values())}\n")
# counts by class and best contaminant organism (what the excluded and the protected sequences are)
byorg = collections.Counter(); byorg_b = collections.Counter()
for r in rows:
    if r[-1] in ("excluded", "contaminant_majority_but_fungal_match_kept"):
        k = (r[-1], r[-4], r[-2] or "NA", r[-3]); byorg[k] += 1; byorg_b[k] += r[1]
with open(os.path.join(a.outdir, f"{a.label}_by_organism.tsv"), "w") as o:
    o.write("set\tclass\tcontaminant_group\torganism\tdatabase_key\tn_" + a.kind + "s\tbases\n")
    for k, c in sorted(byorg.items(), key=lambda x: (x[0][0], -x[1])):
        o.write(f"{a.label}\t{k[0]}\t{k[1]}\t{k[2]}\t{k[3]}\t{c}\t{byorg_b[k]}\n")
crit = {"label": a.label, "kind": a.kind, "rule": "excluded if aligned segments to contaminant groups (bacteria, archaea, virus, human, vector) cover >= min_contam_frac of the length AND no alignment to fungi passes the alignment filter",
        "min_contam_frac": a.min_contam_frac, "min_alignment_length": a.min_aln_len, "min_identity_fungal_residue_matches_over_alignment_length": a.min_identity, "min_identity_contaminant_residue_matches_over_alignment_length": a.min_identity_contaminant,
        "n_alignments_used": nal, "n_screened": len(order), "n_excluded": len(excl),
        "bases_screened": sum(lengths.values()), "bases_excluded": sum(lengths[n] for n in excl)}
json.dump(crit, open(os.path.join(a.outdir, f"{a.label}_criterion.json"), "w"), indent=1)
print(json.dumps(crit))
