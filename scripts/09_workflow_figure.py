#!/usr/bin/env python3
"""Draws the workflow of the whole analysis (inputs, steps 0 to 11, the five evaluations; the names of the jobs, as in the map of the README, are in the boxes) as results/09_summary/fig_workflow.{png,svg}.
Run:  python scripts/09_workflow_figure.py   (RESULTS comes from config/config.sh; matplotlib required)"""
import os
from pathlib import Path
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
R = Path(os.environ.get('RESULTS', Path(__file__).resolve().parent.parent / 'results')); OUT = R / '09_summary'; OUT.mkdir(parents=True, exist_ok=True)
C = {'data': '#E8E8E8', 'prep': '#CFE3F3', 'asm': '#FFE3B3', 'new': '#BFE5D5', 'eval': '#F5D0C5', 'sum': '#DCD3EC'}
JOBCOL = '#1F4E79'
fig, ax = plt.subplots(figsize=(12, 10.1)); ax.set_xlim(0, 12.4); ax.set_ylim(0, 10.4); ax.axis('off')
def box(x, y, w, h, text, col, fs=8, bold=False, jobs=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.02,rounding_size=0.08', fc=C[col], ec='#444444', lw=0.9))
    if jobs:
        ax.text(x + w / 2, y + h - 0.12, text, ha='center', va='top', fontsize=fs, fontweight='bold' if bold else 'normal')
        ax.text(x + w / 2, y + 0.1, jobs, ha='center', va='bottom', fontsize=6.6, family='monospace', color=JOBCOL, linespacing=1.15)
    else: ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fs, fontweight='bold' if bold else 'normal')
def arrow(x1, y1, x2, y2): ax.annotate('', xy=(x2, y2), xytext=(x1, y1), arrowprops=dict(arrowstyle='-|>', color='#333333', lw=1.0, shrinkA=1, shrinkB=1))
def band(y, text): ax.text(0.05, y, text, rotation=90, ha='center', va='center', fontsize=8.5, fontweight='bold', color='#444444')
# data (no job)
band(9.72, 'Data')
for t, x in [('PacBio RS II reads\n5 runs, 15 raw files', 0.4), ('RNA-seq\nHiSeq 175 M pairs\nMiSeq 3.3 M pairs', 3.3), ('Illumina genomic reads\n2013, 37.7 M pairs', 6.2), ('Hw 2.0\npublished assembly', 9.1)]: box(x, 9.25, 2.5, 0.95, t, 'data')
# preparation
band(8.1, 'Preparation')
box(0.4, 7.35, 2.5, 1.55, 'Steps 0 to 3\nsoftware, reference data,\ninput files and checksums', 'prep', jobs='00_preflight, 01_software,\n02_fetch_databases,\n02_screen_db_index (dbindex),\n01_fetch_inputs, check_inputs')
box(3.3, 7.35, 2.5, 1.55, 'Step 4\nraw files to subreads:\nhigh-quality set and filtered set', 'prep', jobs='pacbio, merge, deposited')
box(6.2, 7.35, 2.5, 1.55, 'Step 5\ncontaminant screen\nof the reads', 'prep', jobs='screen_reads')
box(9.1, 7.35, 2.5, 1.55, 'Step 6\nconversion and quality control\nof the RNA-seq and Illumina reads', 'prep', jobs='conv_miseq, conv_hiseq,\nconv_ill, qc\n(the reads are used in steps 9, 10)')
arrow(1.65, 9.25, 3.9, 8.9); arrow(2.9, 8.125, 3.3, 8.125); arrow(5.8, 8.125, 6.2, 8.125); arrow(4.55, 9.25, 9.5, 8.9); arrow(7.45, 9.25, 10.2, 8.9)
# procedure
band(5.98, 'Procedure')
box(0.4, 5.2, 1.95, 1.55, 'Step 7\nseeds: longest reads,\n30 x genome size', 'asm', jobs='proc_r1, proc_r2,\nproc_r3')
box(2.55, 5.2, 1.95, 1.55, 'Step 7\ncorrection: reads aligned\nto seeds, consensus', 'asm', jobs='(the same jobs:\none job does the\nthree boxes)')
box(4.7, 5.2, 1.95, 1.55, 'Step 7\nassembly: Canu (3 runs,\n1 control), Flye (1 control)', 'asm', jobs='(the same jobs) and\nctrl_canu, ctrl_flye')
box(6.85, 5.2, 1.95, 1.55, 'Step 8\npolishing with Quiver', 'asm', jobs='align_*, polish_*')
box(9.0, 5.2, 1.95, 1.55, 'Step 8\nsecond screen: removal of\ncontaminant contigs', 'asm', jobs='remove_*')
box(10.2, 3.75, 1.5, 0.7, 'Hw 2.1', 'new', fs=10, bold=True)
for x in (2.35, 4.5, 6.65, 8.8): arrow(x, 5.975, x + 0.2, 5.975)
arrow(7.45, 7.35, 1.4, 6.75); arrow(9.97, 5.2, 10.8, 4.45)
# evaluations
band(2.4, 'Evaluations')
ax.text(5.0, 3.42, 'Steps 9 and 10: the same five evaluations on Hw 2.0, on Hw 2.1 (3 runs; run 1 also before polishing)\nand on the controls (before and after polishing); also in step 10: scr_*, mito_*, the22 and the22_*,\ngenbank, depth_unscreened (side tables)', ha='center', va='center', fontsize=8, style='italic', linespacing=1.35)
ev = [('1 Contiguity\nN50, L50, NG50, auN', 0.4, 'tests_*'), ('2 Gene space\nBUSCO, RNA-seq,\ntranscripts, proteins', 2.6, 'tests_*, trans_*,\ntrinity (step 9)'), ('3 Structure\nPacBio reads as referee', 4.8, 'tests_*, compare_*'), ('4 Redundancy\ndepth, false duplication', 7.0, 'tests_*'), ('5 Accuracy of bases\nIllumina 2013 reads', 9.2, 'acc_*, shared_*')]
for t, x, j in ev: box(x, 1.75, 2.1, 1.3, t, 'eval', fs=7.5, jobs=j)
arrow(10.9, 3.75, 10.9, 3.05)
ax.plot([11.6, 12.05, 12.05], [9.72, 9.72, 2.4], color='#999999', lw=0.9, ls=(0, (4, 3))); ax.annotate('', xy=(11.3, 2.4), xytext=(12.05, 2.4), arrowprops=dict(arrowstyle='-|>', color='#999999', lw=0.9, ls=(0, (4, 3))))
ax.text(12.25, 6.0, 'Hw 2.0 enters the evaluations', rotation=90, fontsize=7, color='#777777', va='center', ha='center')
# summary
band(0.65, 'Summary')
box(0.4, 0.2, 11.3, 0.95, 'Step 11\ntables and figures; the assessment of each evaluation (better, not worse, worse);\nthe three runs compared; the final assembly Hw2.1.fasta.gz; the check against the expected values', 'sum', fs=8, bold=True, jobs='summary (then hw_run_finished: the message job)')
for x in (1.45, 3.65, 5.85, 8.05, 10.25): arrow(x, 1.75, x, 1.15)
fig.savefig(OUT / 'fig_workflow.png', dpi=200, bbox_inches='tight'); fig.savefig(OUT / 'fig_workflow.svg', bbox_inches='tight'); print('written')
