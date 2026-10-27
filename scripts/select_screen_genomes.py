#!/usr/bin/env python3
"""Choose the reference genomes of the contaminant screen: one genome per genus.

Input : NCBI RefSeq assembly_summary_refseq.txt and the NCBI taxonomy dump (nodes.dmp).
Output: a table (tsv) of the chosen assemblies with group, genus, organism and download address.

Rule (same for bacteria, archaea and fungi): among all RefSeq assemblies of a genus take the one with the
highest rank: reference genome first, then Complete Genome > Chromosome > Scaffold > Contig, then the
longest genome. Assemblies without a genus in the taxonomy are represented one per species.
Hortaea assemblies are never used (the strain under study must not serve as a reference); RefSeq holds none.

Because one genome per genus detects another species of the genus only when it is close (about 90 % identity or more), a short list of
species that are frequent contaminants of sequencing (reagent and laboratory bacteria, skin and gut flora) or live in the hypersaline
habitat of the fungus is added, one genome per listed species (reference genome first, then complete genome). They form the column
part=extra of the table and are stored in the database part "other"; species already chosen as genus representative are not repeated.
"""
import argparse, csv, sys
import pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument("--summary", required=True)
ap.add_argument("--nodes", required=True)
ap.add_argument("--out", required=True)
a = ap.parse_args()

nodes = {}
with open(a.nodes) as fh:
    for line in fh:
        p = line.split("\t|\t")
        nodes[int(p[0])] = (int(p[1]), p[2])

def genus_of(t):
    for _ in range(80):
        if t not in nodes or t == 1:
            return None
        par, rank = nodes[t]
        if rank == "genus":
            return t
        t = par
    return None

d = pd.read_csv(a.summary, sep="\t", skiprows=1, low_memory=False).rename(columns={"#assembly_accession": "acc"})
d = d[d.group.isin(["bacteria", "archaea", "fungi"])].copy()
d = d[~d.organism_name.str.contains("Hortaea", na=False)]
d = d[d.ftp_path.notna() & (d.ftp_path != "na")]
d["genus"] = d.taxid.map(genus_of)
d["key"] = d.genus.map(lambda g: f"g{int(g)}" if pd.notna(g) else None)
d["key"] = d.key.fillna("s" + d.species_taxid.astype(str))
level = {"Complete Genome": 3, "Chromosome": 2, "Scaffold": 1, "Contig": 0}
d["rank"] = (d.refseq_category == "reference genome") * 10 + d.assembly_level.map(level).fillna(0)
d = d.sort_values(["group", "key", "rank", "genome_size"], ascending=[True, True, False, False])
best = d.drop_duplicates(["group", "key"]).copy()
best = best.sort_values(["group", "key"])
best["part"] = "main"
EXTRA = ["Escherichia coli str. K-12", "Staphylococcus aureus", "Staphylococcus epidermidis", "Pseudomonas aeruginosa", "Pseudomonas fluorescens",
         "Pseudomonas putida", "Bacillus subtilis", "Bacillus cereus", "Cutibacterium acnes", "Corynebacterium glutamicum", "Micrococcus luteus",
         "Acinetobacter baumannii", "Klebsiella pneumoniae", "Salmonella enterica", "Enterobacter cloacae", "Ralstonia pickettii",
         "Burkholderia cepacia", "Stenotrophomonas maltophilia", "Sphingomonas paucimobilis", "Bradyrhizobium diazoefficiens", "Streptococcus pneumoniae", "Enterococcus faecalis", "Delftia acidovorans", "Comamonas testosteroni",
         "Halomonas elongata", "Salinibacter ruber", "Haloferax volcanii", "Halobacterium salinarum", "Methanobrevibacter smithii"]
allb = d[d.group.isin(["bacteria", "archaea"])]
ex = []
for name in EXTRA:
    x = allb[allb.organism_name.str.startswith(name)].sort_values("rank", ascending=False)
    if len(x):
        ex.append(x.iloc[0])
    else:
        print("no genome for extra species:", name, file=sys.stderr)
ex = pd.DataFrame(ex).drop_duplicates("acc")
ex = ex[~ex.acc.isin(best.acc)].copy(); ex["part"] = "extra"; ex["key"] = ex.acc
best = pd.concat([best, ex])
cols = ["acc", "group", "key", "taxid", "organism_name", "assembly_level", "refseq_category", "genome_size", "ftp_path", "part"]
best[cols].to_csv(a.out, sep="\t", index=False, quoting=csv.QUOTE_NONE, escapechar="\\")
for g, x in best.groupby(["group", "part"]):
    print(g, len(x), round(x.genome_size.sum() / 1e9, 2), "Gb", file=sys.stderr)
