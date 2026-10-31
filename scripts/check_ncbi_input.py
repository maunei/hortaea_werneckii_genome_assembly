#!/usr/bin/env python
"""Checks the files of the NCBI record of Hw 2.0 that the comparison steps (07a-07c) read: the genome file and the assembly report are found by their exact names,
and the genome file holds every contig of the report, among them the mitochondrial record. Stops with a clear message when not (so that the error appears at the start of the run).
Usage: check_ncbi_input.py INPUT_FOLDER"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hw07_common import *

inp = sys.argv[1] if len(sys.argv) > 1 else os.environ["INPUT"]
genome = ncbi_hw2_file(inp, "genomic.fna.gz"); report = ncbi_hw2_file(inp, "assembly_report.txt")
mito = ncbi_hw2_mito_accession(report)
seqs = read_fasta(genome)
need_record(seqs, mito, genome)
acc = [l.split("\t")[4] for l in open(report, newline=None).read().splitlines() if l and not l.startswith("#")]
missing = [a for a in acc if a not in seqs]
if missing: sys.exit(f"ERROR: {len(missing)} of the {len(acc)} records of {report} are not in {genome} (first: {missing[0]})")
print(f"NCBI record of Hw 2.0 ok: {len(seqs)} sequences in {os.path.basename(genome)}; mitochondrial record {mito} ({len(seqs[mito])} bp)")
