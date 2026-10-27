#!/usr/bin/env python
"""Extract the genome sequence and the protein translations from GenBank flat files of mitochondrial reference genomes.
Usage: 07_mito_refs.py ACC [ACC ...]   (reads gb_<ACC>.gb in the working folder; writes mito_genomes.fasta, mito_proteins.faa, mito_refs.tsv)"""
import sys
from Bio import SeqIO
rows = []
with open("mito_genomes.fasta", "w") as g, open("mito_proteins.faa", "w") as p:
    for acc in sys.argv[1:]:
        rec = SeqIO.read(f"gb_{acc}.gb", "genbank")
        org = rec.annotations.get("organism", "NA").replace(" ", "_")
        g.write(f">{rec.id} {org}\n{str(rec.seq)}\n")
        n = 0
        for f in rec.features:
            if f.type == "CDS" and "translation" in f.qualifiers:
                gene = f.qualifiers.get("gene", f.qualifiers.get("product", ["NA"]))[0].replace(" ", "_")
                p.write(f">{rec.id}|{gene}|{org}\n{f.qualifiers['translation'][0]}\n"); n += 1
        rows.append((rec.id, org, len(rec.seq), n))
with open("mito_refs.tsv", "w") as o:
    o.write("accession\torganism\tlength\tprotein_genes\n")
    for r in rows: o.write("\t".join(map(str, r)) + "\n")
