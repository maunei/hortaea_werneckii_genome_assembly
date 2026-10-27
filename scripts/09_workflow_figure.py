#!/usr/bin/env python3
"""Draws the workflow of the whole analysis (inputs, steps 0 to 11, the five evaluations) as results/09_summary/fig_workflow.{png,svg}.
Run:  python scripts/09_workflow_figure.py   (RESULTS comes from config/config.sh; matplotlib required)"""
import os
from pathlib import Path
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
R = Path(os.environ.get('RESULTS', Path(__file__).resolve().parent.parent / 'results')); OUT = R / '09_summary'; OUT.mkdir(parents=True, exist_ok=True)
C = {'data': '#E8E8E8', 'prep': '#CFE3F3', 'asm': '#FFE3B3', 'new': '#BFE5D5', 'eval': '#F5D0C5', 'sum': '#DCD3EC'}
fig, ax = plt.subplots(figsize=(12, 8.4)); ax.set_xlim(0, 12.4); ax.set_ylim(0, 8.4); ax.axis('off')
def box(x, y, w, h, text, col, fs=8, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.02,rounding_size=0.08', fc=C[col], ec='#444444', lw=0.9))
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fs, fontweight='bold' if bold else 'normal', wrap=True)
def arrow(x1, y1, x2, y2): ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=dict(arrowstyle='-|>', color='#333333', lw=1.0, shrinkA=1, shrinkB=1))
def band(y, text): ax.text(0.05, y, text, rotation=90, ha='center', va='center', fontsize=8.5, fontweight='bold', color='#444444')
# band 1: data
band(7.75, 'Data')
d = [('PacBio RS II reads\n5 runs, 15 raw files', 0.4), ('RNA-seq\nHiSeq 175 M pairs\nMiSeq 3.3 M pairs', 3.3), ('Illumina genomic reads\n2013, 37.7 M pairs', 6.2), ('Hw 2.0\npublished assembly', 9.1)]
for t, x in d: box(x, 7.25, 2.5, 0.95, t, 'data')
# band 2: preparation
band(6.3, 'Preparation')
box(0.4, 5.55, 2.5, 1.05, 'Steps 0 to 3\nsoftware, reference data,\ninput files and checksums', 'prep')
box(3.3, 5.55, 2.5, 1.05, 'Step 4\nraw files to subreads:\nhigh-quality set and filtered set', 'prep')
box(6.2, 5.55, 2.5, 1.05, 'Step 5\ncontaminant screen\nof the reads', 'prep')
box(9.1, 5.55, 2.5, 1.05, 'Step 6\nquality control of the\nRNA-seq and Illumina reads', 'prep')
arrow(1.65, 7.25, 3.9, 6.6); arrow(5.8, 6.07, 6.2, 6.07)
arrow(4.55, 7.25, 9.5, 6.6); arrow(7.45, 7.25, 10.2, 6.6)
# band 3: procedure
band(4.45, 'Procedure')
box(0.4, 3.8, 1.95, 1.05, 'Step 7\nseeds: longest reads,\n30 x genome size', 'asm')
box(2.55, 3.8, 1.95, 1.05, 'Step 7\ncorrection: reads aligned\nto seeds, consensus', 'asm')
box(4.7, 3.8, 1.95, 1.05, 'Step 7\nCanu assembly\n(3 runs, 2 controls)', 'asm')
box(6.85, 3.8, 1.95, 1.05, 'Step 8\npolishing with Quiver', 'asm')
box(9.0, 3.8, 1.95, 1.05, 'Step 8 (05c)\nsecond screen: removal of\ncontaminant contigs', 'asm')
box(10.2, 2.78, 1.5, 0.7, 'Hw 2.1', 'new', fs=10, bold=True)
for x in (2.35, 4.5, 6.65, 8.8): arrow(x, 4.32, x + 0.2, 4.32)
arrow(7.45, 5.55, 1.4, 4.85)
arrow(9.97, 3.8, 10.8, 3.48)
# band 4: evaluations
band(2.05, 'Evaluations')
ev = [('1 Contiguity\nN50, L50, NG50, auN', 0.4), ('2 Gene space\nBUSCO, RNA-seq,\ntranscripts, proteins', 2.6), ('3 Structure\nPacBio reads as referee', 4.8), ('4 Redundancy\ndepth, false duplication', 7.0), ('5 Accuracy of bases\nIllumina 2013 reads', 9.2)]
ax.text(5.9, 2.48, 'Steps 9 and 10: the same five evaluations on Hw 2.0, Hw 2.1 (3 runs) and the polished controls', ha='center', fontsize=8, style='italic')
for t, x in ev: box(x, 1.45, 2.1, 0.85, t, 'eval', fs=7.5)
arrow(10.9, 2.78, 10.9, 2.3)
ax.plot([11.6, 12.05, 12.05], [7.72, 7.72, 1.88], color='#999999', lw=0.9, ls=(0, (4, 3))); ax.annotate('', xy=(11.3, 1.88), xytext=(12.05, 1.88), arrowprops=dict(arrowstyle='-|>', color='#999999', lw=0.9, ls=(0, (4, 3))))
ax.text(12.25, 4.8, 'Hw 2.0 enters the evaluations', rotation=90, fontsize=7, color='#777777', va='center', ha='center')
# band 5: summary
band(0.75, 'Summary')
box(0.4, 0.2, 11.3, 0.8, 'Step 11\ntables and figures; the assessment of each evaluation (better, not worse, worse);\nthe three runs compared; the final assembly Hw2.1.fasta.gz; the check against the expected values', 'sum', fs=8, bold=True)
for x in (1.45, 3.65, 5.85, 8.05, 10.25): arrow(x, 1.45, x, 1.0)
fig.savefig(OUT / 'fig_workflow.png', dpi=200, bbox_inches='tight'); fig.savefig(OUT / 'fig_workflow.svg', bbox_inches='tight'); print('written')
