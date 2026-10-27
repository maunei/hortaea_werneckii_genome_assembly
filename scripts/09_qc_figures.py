#!/usr/bin/env python3
"""Step 09b: quality-control figures and statistics of every kind of sequence data used (PacBio reads, RNA-seq, Illumina 2013, transcripts, depth over Hw 2.1).
Reads results/02_pacbio_reads, results/03_rna_illumina, results/06_transcripts, results/06_tests and the read sets in $WORK/reads/pacbio.
Writes results/09_summary/fig_qc_pacbio.{png,svg}, fig_qc_pacbio_qv.{png,svg}, fig_qc_illumina.{png,svg}, fig_qc_depth.{png,svg} and qc_stats.tsv.
Run:  python scripts/09_qc_figures.py   (HW, RESULTS and WORK come from config/config.sh; matplotlib required)"""
import os, json, csv, gzip, glob
from pathlib import Path
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt, numpy as np
HW = Path(os.environ.get('HW', '.')).resolve(); R = Path(os.environ.get('RESULTS', HW / 'results')); WORK = Path((os.environ.get('WORK') or os.environ['HW_WORK']))
OUT = R / '09_summary'; OUT.mkdir(parents=True, exist_ok=True)
plt.rcParams.update({'font.size': 8, 'axes.spines.top': False, 'axes.spines.right': False, 'figure.dpi': 100})
BLUE, ORANGE, GREEN, GREY = '#0072B2', '#D55E00', '#009E73', '#777777'
def save(fig, name): fig.tight_layout(); fig.savefig(OUT / f'{name}.png', dpi=200); fig.savefig(OUT / f'{name}.svg'); plt.close(fig)
stats = []   # (data, measure, value)
# ---- PacBio: subread lengths of the two read sets, wells and signal per run
def lengths(path):
    L = []
    with open(path) as f:
        for i, l in enumerate(f):
            if i % 4 == 1: L.append(len(l.rstrip('\n')))
    return np.array(L)
sets = {'High-quality set': WORK / 'reads/pacbio/hq_subreads.fastq', 'Filtered set': WORK / 'reads/pacbio/filtered_subreads.fastq'}
H = {}
for k, p in sets.items():
    L = lengths(p); H[k] = L
    s = np.sort(L)[::-1]; cs = np.cumsum(s); n50 = int(s[np.searchsorted(cs, cs[-1] / 2)])
    stats += [(f'PacBio {k.lower()}', 'subreads', f'{len(L):,}'), (f'PacBio {k.lower()}', 'bases (Gb)', f'{L.sum() / 1e9:.2f}'), (f'PacBio {k.lower()}', 'mean length (bases)', f'{L.mean():,.0f}'),
              (f'PacBio {k.lower()}', 'N50 (bases)', f'{n50:,}'), (f'PacBio {k.lower()}', 'median length (bases)', f'{int(np.median(L)):,}'), (f'PacBio {k.lower()}', 'depth over 50 Mb', f'{L.sum() / 50e6:.0f} times')]
runs = sorted(glob.glob(str(R / '02_pacbio_reads/SRR*_bax_metrics.json')))
M = {}
for f in runs:
    d = json.load(open(f)); rid = Path(f).name.split('_')[0]; M[rid] = d
fig, ax = plt.subplots(1, 3, figsize=(10.5, 3.3))
bins = np.arange(0, 24000, 500)
for k, c in (('High-quality set', BLUE), ('Filtered set', ORANGE)): ax[0].hist(H[k], bins=bins, histtype='step', color=c, lw=1.4, label=k)
ax[0].set_xlabel('Subread length (bases)'); ax[0].set_ylabel('Subreads'); ax[0].legend(frameon=False); ax[0].set_title('a  Subread lengths', loc='left', fontsize=9)
ids = list(M); x = np.arange(len(ids)); prod = [sum(v['productive_P1'] for v in M[i].values()) for i in ids]; emp = [sum(v['empty_P0'] for v in M[i].values()) for i in ids]; oth = [sum(v['other_P2'] for v in M[i].values()) for i in ids]
tot = [a + b + c for a, b, c in zip(prod, emp, oth)]
ax[1].bar(x, [p / t * 100 for p, t in zip(prod, tot)], color=BLUE, label='Productive (one active polymerase)'); ax[1].bar(x, [o / t * 100 for o, t in zip(oth, tot)], bottom=[p / t * 100 for p, t in zip(prod, tot)], color=GREY, label='Other (several polymerases)'); ax[1].bar(x, [e / t * 100 for e, t in zip(emp, tot)], bottom=[(p + o) / t * 100 for p, o, t in zip(prod, oth, tot)], color='#CCCCCC', label='Empty')
ax[1].set_xticks(x); ax[1].set_xticklabels([i.replace('SRR', '') for i in ids], fontsize=7); ax[1].set_xlabel('Sequencing run (SRR number)'); ax[1].set_ylabel('Wells (%)'); ax[1].legend(frameon=False, fontsize=6.5, loc='upper center', bbox_to_anchor=(0.5, -0.28)); ax[1].set_title('b  Wells of the SMRT cells', loc='left', fontsize=9)
snr = {i: np.mean([v['snr_mean_ACGT'] for v in M[i].values()], axis=0) for i in ids}; w = 0.2
for j, (b, c) in enumerate(zip('ACGT', ['#009E73', '#0072B2', '#E69F00', '#D55E00'])): ax[2].bar(x + (j - 1.5) * w, [snr[i][j] for i in ids], w, color=c, label=b)
ax[2].set_xticks(x); ax[2].set_xticklabels([i.replace('SRR', '') for i in ids], fontsize=7); ax[2].set_xlabel('Sequencing run (SRR number)'); ax[2].set_ylabel('Mean signal-to-noise ratio'); ax[2].set_ylim(0, 15); ax[2].legend(frameon=False, ncol=4, title='Base', fontsize=7, loc='upper center'); ax[2].set_title('c  Signal per base channel', loc='left', fontsize=9)
save(fig, 'fig_qc_pacbio')
rs = [np.mean([v['readscore_mean_P1'] for v in M[i].values()]) for i in ids]; fr = [np.mean([v['frac_readscore_ge_0_80'] for v in M[i].values()]) for i in ids]
stats += [('PacBio wells', 'productive wells (%)', f'{sum(prod) / sum(tot) * 100:.1f}'), ('PacBio wells', 'mean read score of productive wells', f'{np.mean(rs):.2f}'), ('PacBio wells', 'productive wells with read score of at least 0.80 (%)', f'{np.mean(fr) * 100:.1f}'),
          ('PacBio wells', 'mean signal-to-noise ratio (A, C, G, T)', ', '.join(f'{v:.1f}' for v in np.mean([snr[i] for i in ids], axis=0)))]
# ---- PacBio quality information that comes with the reads: read score (rq) and the quality-value tracks of the BAM files (insertion, deletion, substitution, merge)
import subprocess, collections
SAM = os.environ.get('QC_BIN', '') + '/samtools'
bams = sorted(glob.glob(str(WORK / 'pacbio_bam/SRR*/SRR*.subreads.bam')))
rq = []; qv = {t: np.zeros(100, dtype=np.int64) for t in ('iq', 'dq', 'sq', 'mq')}; qvread = {t: [] for t in qv}; gcs = []; nread = 0
for bam in bams:
    pr = subprocess.Popen([SAM, 'view', bam], stdout=subprocess.PIPE, text=True, bufsize=1 << 20)
    for i, l in enumerate(pr.stdout):
        if i % 20: continue                     # every 20th subread of every run
        t = l.rstrip('\n').split('\t'); seq = t[9]; tags = {x[:2]: x[5:] for x in t[11:] if len(x) > 5}
        if 'rq' in tags: rq.append(float(tags['rq']))
        for k in qv:
            if k in tags:
                a = np.frombuffer(tags[k].encode(), dtype=np.uint8).astype(int) - 33; qv[k] += np.bincount(np.clip(a, 0, 99), minlength=100); qvread[k].append(a.mean())
        gcs.append((seq.count('G') + seq.count('C')) / max(len(seq), 1) * 100); nread += 1
    pr.stdout.close(); pr.wait()
rq = np.array(rq); gcs = np.array(gcs)
fig, ax = plt.subplots(1, 3, figsize=(10.5, 3.3))
ax[0].hist(rq, bins=np.arange(0.7, 1.0001, 0.005), color=BLUE); ax[0].axvline(0.80, color=ORANGE, lw=1.2, ls='--'); ax[0].text(0.91, ax[0].get_ylim()[1] * 0.9, 'dashed line:\nread score 0.80\n(filter of the\noriginal protocol)', fontsize=6.5, color=ORANGE, va='top'); ax[0].set_xlim(0.69, 1.0)
ax[0].set_xlabel('Read score of the polymerase read (rq)'); ax[0].set_ylabel('Subreads (sample)'); ax[0].set_title('a  Read score', loc='left', fontsize=9)
for k, c, lab in (('iq', BLUE, 'Insertion QV'), ('dq', ORANGE, 'Deletion QV'), ('sq', GREEN, 'Substitution QV'), ('mq', GREY, 'Merge QV')):
    h = qv[k][:60]; ax[1].plot(np.arange(60), h / h.sum() * 100, color=c, lw=1.3, label=lab)
ax[1].set_xlabel('Quality value of a base (Phred scale)'); ax[1].set_ylabel('Bases (%) of the sampled subreads'); ax[1].legend(frameon=False, fontsize=6.5); ax[1].set_title('b  Quality-value tracks', loc='left', fontsize=9)
ax[2].hist(gcs, bins=np.arange(30, 75, 1), color=BLUE); ax[2].axvline(53.5, color=GREY, lw=0.8, ls=':'); ax[2].text(62, ax[2].get_ylim()[1] * 0.9, 'dotted line:\nGC of Hw 2.1\n(53.5 %)', fontsize=6.5, color=GREY, va='top')
ax[2].set_xlabel('GC content of a subread (%)'); ax[2].set_ylabel('Subreads (sample)'); ax[2].set_title('c  GC content per subread', loc='left', fontsize=9)
save(fig, 'fig_qc_pacbio_qv')
stats += [('PacBio quality tracks (sample)', 'subreads sampled (every 20th of the five runs)', f'{nread:,}'), ('PacBio quality tracks (sample)', 'mean read score (rq)', f'{rq.mean():.3f}'),
          ('PacBio quality tracks (sample)', 'mean quality value, insertion / deletion / substitution / merge', ' / '.join(f'{np.mean(qvread[k]):.1f}' for k in ('iq', 'dq', 'sq', 'mq'))),
          ('PacBio quality tracks (sample)', 'mean GC of a subread (%)', f'{gcs.mean():.1f}')]
# ---- RNA-seq and Illumina 2013: per-cycle quality, insert size, base content
names = {'SRR5086622': 'RNA-seq HiSeq (SRR5086622)', 'SRR5086621': 'RNA-seq MiSeq (SRR5086621)', 'SRR866616': 'Illumina genomic 2013 (SRR866616)'}; cols = {'SRR5086622': BLUE, 'SRR5086621': GREEN, 'SRR866616': ORANGE}
fig, ax = plt.subplots(1, 3, figsize=(10.5, 3.3))
for r in names:
    d = json.load(open(R / f'03_rna_illumina/fastp/{r}.json'))
    for m, ls in (('read1_before_filtering', '-'), ('read2_before_filtering', '--')):
        q = d[m]['quality_curves']['mean']; ax[0].plot(np.arange(1, len(q) + 1), q, ls, color=cols[r], lw=1.3, label=names[r] if m.startswith('read1') else None)
    h = np.array(d['insert_size']['histogram'], float); ax[1].plot(np.arange(len(h)), h / h.sum() * 100, color=cols[r], lw=1.3, label=names[r])
    c = d['read1_before_filtering']['content_curves']
    s = d['summary']['before_filtering']
    stats += [(names[r], 'read pairs', f"{d['read1_before_filtering']['total_reads']:,}"), (names[r], 'read length (bases)', str(s['read1_mean_length'])), (names[r], 'bases at Q30 or better (%)', f"{s['q30_rate'] * 100:.1f}"),
              (names[r], 'GC content (%)', f"{s['gc_content'] * 100:.1f}"), (names[r], 'insert size at the peak (bases)', str(d['insert_size']['peak'])), (names[r], 'duplication (%)', f"{d['duplication']['rate'] * 100:.1f}"),
              (names[r], 'reads with adapter trimmed (%)', f"{d['adapter_cutting']['adapter_trimmed_reads'] / d['summary']['before_filtering']['total_reads'] * 100:.1f}")]
ax[0].axhline(30, color=GREY, lw=0.7, ls=':'); ax[0].text(2, 30.6, 'Q30', fontsize=7, color=GREY); ax[0].set_xlabel('Position in the read (cycle)'); ax[0].set_ylabel('Mean base quality (Phred)'); ax[0].set_ylim(20, 40); ax[0].legend(frameon=False, fontsize=6.5, loc='lower left'); ax[0].set_title('a  Quality per cycle (solid: mate 1, dashed: mate 2)', loc='left', fontsize=8)
ax[1].set_xlim(0, 400); ax[1].set_ylim(0, 3); ax[1].set_xlabel('Insert size (bases)'); ax[1].set_ylabel('Read pairs (%), axis cut at 3 %'); ax[1].set_title('b  Fragment length seen by fastp', loc='left', fontsize=9)
ax[1].text(395, 2.7, 'Only fragments short enough for the two mates\nto overlap by 30 bases or more can be measured\n(up to 2 x read length - 30). The 2013 library\nhas a spike at 76 bases (the read length), cut\nby the axis.', fontsize=6.5, color=ORANGE, ha='right', va='top')
rates = {}
for r in names:
    d = json.load(open(R / f'03_rna_illumina/fastp/{r}.json')); sb = d['summary']['before_filtering']
    rates[r] = [sb['q30_rate'] * 100, d['duplication']['rate'] * 100, d['adapter_cutting']['adapter_trimmed_reads'] / sb['total_reads'] * 100]
labs = ['Bases at Q30\nor better', 'Duplicated\nreads', 'Reads with\nadapter']; xx = np.arange(3)
for j, r in enumerate(names): ax[2].bar(xx + (j - 1) * 0.27, rates[r], 0.27, color=cols[r], label=names[r])
ax[2].set_xticks(xx); ax[2].set_xticklabels(labs); ax[2].set_ylabel('Percent'); ax[2].set_title('c  Summary rates (colours as in a)', loc='left', fontsize=9)
save(fig, 'fig_qc_illumina')
# ---- depth of the PacBio reads over Hw 2.1 (1 kb windows) and over Hw 2.0
fig, ax = plt.subplots(1, 2, figsize=(7.5, 3.1))
for a, c, lab in (('hw2', ORANGE, 'Hw 2.0'), ('proc_r1', BLUE, 'Hw 2.1')):
    p = R / f'06_tests/{a}/depth_1kb_windows.bed.gz'; D = []; Ln = []
    with gzip.open(p, 'rt') as f:
        for l in f: t = l.split('\t'); D.append(float(t[3])); Ln.append(int(t[2]) - int(t[1]))
    D = np.array(D); Ln = np.array(Ln); o = np.argsort(D); cw = np.cumsum(Ln[o]); med = D[o][np.searchsorted(cw, cw[-1] / 2)]
    ax[0].hist(D / med, bins=np.arange(0, 3.05, 0.05), weights=Ln / Ln.sum() * 100, histtype='step', color=c, lw=1.4, label=f'{lab} (median depth {med:.1f} times)')
    stats += [(f'PacBio depth over {lab}', 'median depth (times)', f'{med:.1f}'), (f'PacBio depth over {lab}', 'bases in windows at 0.5 to 1.5 times the median (%)', f'{Ln[(D / med >= 0.5) & (D / med <= 1.5)].sum() / Ln.sum() * 100:.1f}')]
ax[0].set_xlabel('Depth of a 1-kb window divided by the median depth'); ax[0].set_ylabel('Percent of the assembly (bases)'); ax[0].legend(frameon=False, fontsize=7); ax[0].set_title('a  Depth is even along the assembly', loc='left', fontsize=9)
tj = json.load(open(R / '06_transcripts/trinity_assembly.json'))
ax[1].axis('off'); ax[1].set_title('b  Transcripts assembled without a genome (Trinity)', loc='left', fontsize=9)
rows = [('Transcripts', f"{tj['sequences']:,}"), ('Total bases', f"{tj['total_bases']:,}"), ('N50 (bases)', f"{tj['n50']:,}"), ('Longest (bases)', f"{tj['longest']:,}"), ('Shortest (bases)', f"{tj['shortest']:,}"), ('Read pairs used', f"{int(tj['read_pairs_used']):,}")]
ax[1].table(cellText=rows, colLabels=['Measure', 'Value'], loc='center', cellLoc='left', colWidths=[0.55, 0.4]).scale(1, 1.3)
save(fig, 'fig_qc_depth')
stats += [('Transcripts assembled without a genome', 'transcripts', f"{tj['sequences']:,}"), ('Transcripts assembled without a genome', 'total bases', f"{tj['total_bases']:,}"), ('Transcripts assembled without a genome', 'N50 (bases)', f"{tj['n50']:,}"),
          ('Transcripts assembled without a genome', 'read pairs used', f"{int(tj['read_pairs_used']):,}"), ('Transcripts assembled without a genome', 'wall time and peak memory', f"{tj['wall_time']}; {tj['peak_memory_gb']} GB")]
with open(OUT / 'qc_stats.tsv', 'w') as w:
    w.write('data\tmeasure\tvalue\n')
    for a, b, c in stats: w.write(f'{a}\t{b}\t{c}\n')
print(len(stats), 'statistics written')
