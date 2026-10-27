#!/usr/bin/env python3
"""Step 09: summary tables, noise scale, verdict (the criteria of section 3 of the report) and figures.
Reads results/06_tests, 06_transcripts, 07_compare, 08_illumina_accuracy, 07_comparator for every assembly that has results; writes results/09_summary/.
Usage: python scripts/09_summary.py   (from the workflow folder; RESULTS and WORK are read from the environment, set by config/config.sh)"""
import json, os, sys, math, csv
from pathlib import Path
HW = Path(os.environ.get('HW', '.')).resolve(); R = Path(os.environ.get('RESULTS', HW / 'results')); WORK = Path((os.environ.get('WORK') or os.environ['HW_WORK']))
OUT = R / '09_summary'; OUT.mkdir(parents=True, exist_ok=True)
NEW = ['proc_r1', 'proc_r2', 'proc_r3']                 # polished runs of the procedure (the noise scale is their range)
OTHER = ['proc_r1_raw', 'ctrl_canu', 'ctrl_flye', 'ctrl_canu_quiver', 'ctrl_flye_quiver', 'hw2']
ORDER = ['hw2'] + NEW + ['proc_r1_raw', 'ctrl_canu', 'ctrl_flye', 'ctrl_canu_quiver', 'ctrl_flye_quiver']
LABEL = {'hw2': 'Hw 2.0 (GitHub)', 'proc_r1': 'Procedure, run 1', 'proc_r2': 'Procedure, run 2', 'proc_r3': 'Procedure, run 3', 'proc_r1_raw': 'Procedure, run 1, before polishing',
         'ctrl_canu': 'Control: Canu, default', 'ctrl_flye': 'Control: Flye, default', 'ctrl_canu_quiver': 'Control: Canu, default, polished with Quiver', 'ctrl_flye_quiver': 'Control: Flye, default, polished with Quiver'}
FIGSET = ['hw2', 'proc_r1', 'proc_r2', 'proc_r3', 'ctrl_canu_quiver', 'ctrl_flye_quiver']      # assemblies shown in the figures
FIGLABEL = {'hw2': 'Hw 2.0', 'proc_r1': 'Hw 2.1, run 1', 'proc_r2': 'Hw 2.1, run 2', 'proc_r3': 'Hw 2.1, run 3', 'ctrl_canu_quiver': 'Canu default, polished', 'ctrl_flye_quiver': 'Flye default, polished'}
def J(path):
    p = R / path
    return json.load(open(p)) if p.exists() else None
def get(d, key):
    for k in key.split('.'):
        if d is None or k not in d: return None
        d = d[k]
    return d
# measure: (id, line, label, source file template, key, higher_is_better or None (descriptive), format)
M = [
 ('contigs', 1, 'Contigs', '06_tests/{a}/summary.json', 'contiguity.all.contigs', None, '{:,.0f}'),
 ('total_bp', 1, 'Total length (bases)', '06_tests/{a}/summary.json', 'contiguity.all.total_bp', None, '{:,.0f}'),
 ('n50', 1, 'N50 (bases)', '06_tests/{a}/summary.json', 'contiguity.all.n50', True, '{:,.0f}'),
 ('l50', 1, 'L50 (contigs)', '06_tests/{a}/summary.json', 'contiguity.all.l50', False, '{:,.0f}'),
 ('ng50', 1, 'NG50 (bases, genome size 50 Mb)', '06_tests/{a}/summary.json', 'contiguity.all.ng50', True, '{:,.0f}'),
 ('aun', 1, 'auN (bases)', '06_tests/{a}/summary.json', 'contiguity.all.aun', True, '{:,.0f}'),
 ('longest', 1, 'Longest contig (bases)', '06_tests/{a}/summary.json', 'contiguity.all.longest', None, '{:,.0f}'),
 ('busco_complete', 2, 'BUSCO complete (%)', '06_tests/{a}/summary.json', 'busco.complete_percent', True, '{:.1f}'),
 ('busco_dup', 2, 'BUSCO complete, duplicated (%)', '06_tests/{a}/summary.json', 'busco.duplicated_percent', None, '{:.1f}'),
 ('star_unique', 2, 'RNA read pairs aligned to one place (%)', '06_tests/{a}/summary.json', 'star.frac_unique', True, '{:.2%}'),
 ('transcripts', 2, 'Transcripts aligned over 90 % of length at 95 % identity (%)', '06_transcripts/{a}/summary.json', 'frac_pass_ge90pct_ge95id', True, '{:.2%}'),
 ('proteins_whole', 2, 'Swiss-Prot fungal proteins found whole (%)', '06_tests/{a}/summary.json', 'miniprot.frac_proteins_whole', None, '{:.2%}'),
 ('readback80', 3, 'PacBio reads aligned over 80 % of their length (%)', '06_tests/{a}/summary.json', 'readback.frac_reads_aligned_ge80pct', True, '{:.2%}'),
 ('readback_pieces', 3, 'PacBio reads aligned in pieces (%)', '06_tests/{a}/summary.json', 'readback.frac_reads_in_pieces', False, '{:.2%}'),
 ('unspanned', 3, 'Bases not spanned by any read across a junction', '06_tests/{a}/summary.json', 'readback.unspanned_bases', False, '{:,.0f}'),
 ('discordant', 3, 'Interior junctions with discordant read pairs', '06_tests/{a}/summary.json', 'readback.discordant_junction_clusters_interior_ge_min_reads', False, '{:,.0f}'),
 ('adjud_for_new', 3, 'Disagreements with Hw 2.0 decided for this assembly (proportion of decided)', '07_compare/{a}_vs_hw2/summary.json', 'fraction_of_decided_for_A.proportion', True, '{:.1%}'),
 ('depth_ok', 4, 'Bases in windows at 0.5 to 1.5 times the median PacBio depth (%)', '06_tests/{a}/summary.json', 'depth.frac_0_5_to_1_5', True, '{:.2%}'),
 ('false_dup', 4, 'Bases with a best partner at 98 % identity or more (%)', '06_tests/{a}/summary.json', 'redundancy.false_duplication_fraction', False, '{:.2%}'),
 ('real_similar', 4, 'Bases with a best partner at 80 to 95 % identity (%)', '06_tests/{a}/summary.json', 'redundancy.real_similar_fraction', None, '{:.1%}'),
 ('diff_total', 5, 'Illumina differences per Mb (all)', '08_illumina_accuracy/{a}/summary.json', 'differences.per_mb_callable.total', None, '{:.1f}'),
 ('diff_specific', 5, 'Specific differences per Mb (all)', '08_illumina_accuracy/shared/{a}_vs_hw2/summary.json', 'assemblies.{a}.specific_per_mb_callable.all', False, '{:.1f}'),
 ('diff_specific_snv', 5, 'Specific single-base differences per Mb', '08_illumina_accuracy/shared/{a}_vs_hw2/summary.json', 'assemblies.{a}.specific_per_mb_callable.snv', None, '{:.1f}'),
 ('diff_specific_indel', 5, 'Specific insertions and deletions per Mb', '08_illumina_accuracy/shared/{a}_vs_hw2/summary.json', None, None, '{:.1f}'),
 ('mapped', 5, 'Illumina read pairs mapped (%)', '08_illumina_accuracy/{a}/summary.json', 'mapping.percent_mapped', None, '{:.2f}'),
]
def value(a, m):
    mid, line, label, tmpl, key, hib, fmt = m
    if a == 'hw2' and mid == 'adjud_for_new': return None
    if mid == 'diff_specific' and a == 'hw2':
        d = J('08_illumina_accuracy/shared/proc_r1_vs_hw2/summary.json')
        return get(d, 'assemblies.hw2.specific_per_mb_callable.all') if d else None
    if mid == 'diff_specific_indel' and a == 'hw2':
        d = J('08_illumina_accuracy/shared/proc_r1_vs_hw2/summary.json'); sp = get(d, 'assemblies.hw2.specific_per_mb_callable'); return None if sp is None else sp['ins'] + sp['del']
    if mid == 'diff_specific_snv' and a == 'hw2':
        d = J('08_illumina_accuracy/shared/proc_r1_vs_hw2/summary.json'); return get(d, 'assemblies.hw2.specific_per_mb_callable.snv') if d else None
    d = J(tmpl.format(a=a))
    if d is None: return None
    if mid == 'diff_specific_indel':
        s = get(d, f'assemblies.{a}.specific_per_mb_callable')
        return None if s is None else s['ins'] + s['del']
    return get(d, key.format(a=a))
V = {a: {m[0]: value(a, m) for m in M} for a in ORDER}
# wide table
with open(OUT / 'measures.tsv', 'w') as w:
    w.write('measure\tline\t' + '\t'.join(ORDER) + '\n')
    for m in M:
        w.write(f'{m[0]}\t{m[1]}\t' + '\t'.join('' if V[a][m[0]] is None else repr(V[a][m[0]]) for a in ORDER) + '\n')
# noise scale and comparison with Hw 2.0
runs = [a for a in NEW if V[a]['n50'] is not None]
rows = []; state = {}
for m in M:
    mid, line, label, tmpl, key, hib, fmt = m
    vals = [V[a][mid] for a in runs if V[a][mid] is not None]
    hw = V['hw2'][mid]
    if not vals: continue
    mean = sum(vals) / len(vals); lo, hi = min(vals), max(vals); noise = hi - lo
    row = dict(measure=mid, line=line, label=label, runs=len(vals), mean=mean, min=lo, max=hi, noise=noise, hw2=hw)
    if hib is not None and hw is not None and mid != 'adjud_for_new':
        delta = mean - hw
        if abs(delta) <= noise: st = 'within noise'
        else: st = 'better' if (delta > 0) == hib else 'worse'
        row.update(delta=delta, state=st, rel=(100 * delta / abs(hw) if hw else None))
    rows.append(row)
# adjudication: interval rule for every run (Wilson 95 %) on the proportion of decided disagreements decided for the new assembly
adj = {}
for a in runs:
    d = J(f'07_compare/{a}_vs_hw2/summary.json')
    if d: adj[a] = dict(share=d['fraction_of_decided_for_A']['proportion'], lo=d['fraction_of_decided_for_A']['ci95_low'], hi=d['fraction_of_decided_for_A']['ci95_high'],
                        decided=d['fraction_of_decided_for_A']['of'], for_new=d['decided_for_A']['count'], for_hw2=d['decided_for_B']['count'], disagreements=d['disagreements'])
def adj_state():
    if not adj: return None
    if all(v['lo'] > 0.5 for v in adj.values()): return 'better'
    if all(v['hi'] < 0.5 for v in adj.values()): return 'worse'
    if all(v['hi'] < 0.5 or v['lo'] > 0.5 for v in adj.values()) and len({v['lo'] > 0.5 for v in adj.values()}) > 1: return 'mixed between runs'
    return 'interval includes one half'
S = {r['measure']: r.get('state') for r in rows}
def line_verdict(line):
    keys = {1: ['n50', 'ng50', 'aun', 'l50'], 2: ['busco_complete', 'transcripts'], 4: ['false_dup', 'depth_ok'], 5: ['diff_specific']}
    if line == 3:
        s = adj_state(); return s, {'adjudication': s}
    sts = {k: S.get(k) for k in keys[line] if S.get(k) is not None}
    if not sts: return None, sts
    v = set(sts.values())
    if 'worse' in v: res = 'worse'
    elif v == {'better'}: res = 'better'
    elif 'better' in v: res = 'not worse (better in part)'
    else: res = 'not worse (within noise)'
    return res, sts
verdict = {}
for line in (1, 2, 3, 4, 5):
    res, sts = line_verdict(line); verdict[line] = dict(verdict=res, measures=sts)
better_lines = [l for l, v in verdict.items() if v['verdict'] and v['verdict'].startswith('better')]
worse_lines = [l for l, v in verdict.items() if v['verdict'] == 'worse' or (l == 3 and v['verdict'] in ('worse', 'mixed between runs'))]
overall = ('The new assembly is better than Hw 2.0 by the rules of the plan' if (verdict[1]['verdict'] == 'better' and len(better_lines) >= 2 and not worse_lines)
           else 'The rules for "better" are not all met; the lines are reported as they are')
with open(OUT / 'noise_scale.tsv', 'w') as w:
    w.write('measure\tline\truns\tmean\tmin\tmax\tnoise_range\thw2\tdifference\tstate\n')
    for r in rows:
        w.write('\t'.join(str(x) for x in (r['measure'], r['line'], r['runs'], r['mean'], r['min'], r['max'], r['noise'], '' if r['hw2'] is None else r['hw2'], r.get('delta', ''), r.get('state', ''))) + '\n')
json.dump(dict(verdict=verdict, overall=overall, adjudication=adj, runs_used=runs, rule='difference counts only if |mean of the runs - Hw 2.0| exceeds the range over the runs'), open(OUT / 'verdict.json', 'w'), indent=1)
with open(OUT / 'verdict.tsv', 'w') as w:
    w.write('line\tverdict\tmeasures\n')
    for l, v in verdict.items(): w.write(f"{l}\t{v['verdict']}\t{json.dumps(v['measures'])}\n")
# formatted table for the README: one row per measure
def f(m, x): return '' if x is None else m[6].format(x)
STATE = {r['measure']: r for r in rows}
with open(OUT / 'results_table.tsv', 'w') as w:
    w.write('line\tmeasure\thw2\tprocedure_mean\tprocedure_range\tversus_hw2\tchange_percent\tproc_r1_raw\tctrl_canu\tctrl_flye\tctrl_canu_quiver\tctrl_flye_quiver\tmeasure_id\n')
    for m in M:
        r = STATE.get(m[0]); mean = f(m, r['mean']) if r else ''; rng = ''
        if r: rng = f(m, r['min']) + ' to ' + f(m, r['max']) if r['runs'] > 1 else 'one run'
        w.write('\t'.join([str(m[1]), (m[2].replace(' (%)', '') if '%}' in m[6] else m[2]), f(m, V['hw2'][m[0]]), mean, rng, (r or {}).get('state', ''), ('' if not r or r.get('rel') is None else f"{r['rel']:+.1f}"), f(m, V['proc_r1_raw'][m[0]]), f(m, V['ctrl_canu'][m[0]]), f(m, V['ctrl_flye'][m[0]]), f(m, V['ctrl_canu_quiver'][m[0]]), f(m, V['ctrl_flye_quiver'][m[0]]), m[0]]) + '\n')
print(overall); [print(l, v['verdict'], v['measures']) for l, v in verdict.items()]
# figures
try:
    import matplotlib; matplotlib.use('Agg'); matplotlib.rcParams['svg.fonttype'] = 'path'; import matplotlib.pyplot as plt
    COL = {'hw2': '#D55E00', 'proc': '#0072B2', 'proc_r1_raw': '#56B4E9', 'ctrl_canu': '#E69F00', 'ctrl_flye': '#009E73', 'ctrl_canu_quiver': '#E69F00', 'ctrl_flye_quiver': '#009E73'}
    def col(a): return COL['proc'] if a in NEW else COL[a]
    def lengths(a):
        p = WORK / 'asm' / a / 'final.fasta'
        if not p.exists(): return None
        L = []; n = 0
        for l in open(p):
            if l[0] == '>':
                if n: L.append(n)
                n = 0
            else: n += len(l.strip())
        L.append(n); return sorted(L, reverse=True)
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    for a in FIGSET:
        L = lengths(a)
        if not L: continue
        cum = 0; xs = [0]; ys = [0]
        for x in L: cum += x; xs.append(cum / 1e6); ys.append(x / 1e3)
        xs = [0] + [c / 1e6 for c in __import__('itertools').accumulate(L)]
        ax.step(xs[1:], [x / 1e3 for x in L], where='post', color=col(a), lw=2 if a in ('hw2', 'proc_r1') else 1.3, alpha=0.95 if a not in ('proc_r2', 'proc_r3') else 0.6, label=FIGLABEL[a].replace(', run 1', '') if a not in ('proc_r2', 'proc_r3') else None)
    ax.axvline(25, color='#999999', lw=0.8, ls=':'); ax.text(25.4, 0.04, 'half of the assembly', fontsize=8, color='#555555', transform=ax.get_xaxis_transform())
    ax.set_yscale('log'); ax.set_xlabel('Cumulative length of the contigs, from the longest (Mb)'); ax.set_ylabel('Contig length (kb)')
    ax.legend(fontsize=8, frameon=False, loc='lower left'); fig.tight_layout(); fig.savefig(OUT / 'fig_contigs.png', dpi=200); fig.savefig(OUT / 'fig_contigs.svg'); plt.close(fig)
    # key measures: one panel each, assemblies as points, noise range of the three runs as a band
    keys = [('n50', 'N50 (kb)', 1e-3), ('busco_complete', 'BUSCO complete (%)', 1), ('transcripts', 'Transcripts aligned (%)', 100), ('readback80', 'Reads aligned over 80 % (%)', 100),
            ('false_dup', 'False duplication (% of bases)', 100), ('diff_specific', 'Specific Illumina differences per Mb', 1)]
    fig, axes = plt.subplots(2, 3, figsize=(10.5, 5.6)); axes = axes.ravel()
    for ax, (k, lab, f) in zip(axes, keys):
        names = [a for a in FIGSET if V[a][k] is not None]
        for i, a in enumerate(names): ax.scatter(V[a][k] * f, i, color=col(a), s=40, zorder=3)
        rr = [V[a][k] * f for a in NEW if V[a][k] is not None]
        if rr: ax.axvspan(min(rr), max(rr), color=COL['proc'], alpha=0.15, lw=0)
        ax.set_yticks(range(len(names))); ax.set_yticklabels([FIGLABEL[a] for a in names], fontsize=7); ax.invert_yaxis(); ax.set_xlabel(lab, fontsize=8); ax.tick_params(labelsize=7)
    fig.tight_layout(); fig.savefig(OUT / 'fig_measures.png', dpi=200); fig.savefig(OUT / 'fig_measures.svg'); plt.close(fig)
except Exception as e:
    print('figures not made:', e)
