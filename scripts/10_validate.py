#!/usr/bin/env python3
"""Step 10: validation of a rerun.
  python scripts/10_validate.py make-expected RESULTS_DIR      writes validation/expected.tsv from the results of the run reported in the README
  python scripts/10_validate.py check RESULTS_DIR [OUT]        compares the results of a rerun with validation/expected.tsv and writes a pass/fail report
Rules (section 7 and 10 of the plan): a measure of the procedure (runs proc_r1 to proc_r3) must lie inside the range seen over the three runs of the reported run,
widened on both sides by that range or by 0.5 percent of the mean, whichever is larger (the three runs of the reported run are identical, so the range alone would be zero); counts of reads and the measures of Hw 2.0 must agree to 0.2 percent (they do not depend on the assembler);
the measures of the control runs must agree to 25 percent (single runs of Flye and Canu, which differ from run to run) and the transcript measure (Trinity differs at every run) to 1.5 percent."""
import sys, os, json, csv
from pathlib import Path
HW = Path(os.environ.get('HW', Path(__file__).resolve().parent.parent))
def read_measures(res):
    rows = list(csv.reader(open(Path(res) / '09_summary' / 'measures.tsv'), delimiter='\t')); hdr = rows[0]; out = {}
    for r in rows[1:]:
        for a, v in zip(hdr[2:], r[2:]):
            if v != '': out[(r[0], a)] = float(v)
    return out, hdr[2:]
def read_counts(res):
    c = {}
    for name, f, key in (('pacbio_hq_reads', '02_pacbio_reads/merged_seqkit_stats.tsv', 'hq_subreads.fastq'), ('pacbio_filtered_reads', '02_pacbio_reads/merged_seqkit_stats.tsv', 'filtered_subreads.fastq')):
        for r in csv.DictReader(open(Path(res) / f), delimiter='\t'):
            if r['file'] == key: c[name] = float(r['num_seqs'])
    return c
mode = sys.argv[1]; res = sys.argv[2]
if mode == 'make-expected':
    M, assemblies = read_measures(res); counts = read_counts(res)
    meas = sorted({k[0] for k in M})
    with open(HW / 'validation' / 'expected.tsv', 'w') as w:
        w.write('item\tgroup\texpected\tlow\thigh\trule\n')
        for k, v in counts.items(): w.write(f'{k}\tcounts\t{v}\t{v}\t{v}\texact\n')
        for m in meas:
            runs = [M[(m, a)] for a in ('proc_r1', 'proc_r2', 'proc_r3') if (m, a) in M]
            if runs:
                lo, hi = min(runs), max(runs); mean = sum(runs) / len(runs); tr = (m == 'transcripts'); n = 0.015 * abs(mean) if tr else max(hi - lo, 0.005 * abs(mean))
                rule = 'inside the range of the runs widened by 1.5 percent of the mean (the transcripts come from Trinity, which gives a slightly different assembly at every run: 0.5 and 0.6 percent in two reruns)' if tr else 'inside the range of the runs widened by the range or by 0.5 percent of the mean (the larger)'
                w.write(f'{m}:procedure\tprocedure\t{mean}\t{lo - n}\t{hi + n}\t{rule}\n')
            if (m, 'hw2') in M:
                v = M[(m, 'hw2')]; tr = (m == 'transcripts'); t = abs(v) * (0.015 if tr else 0.002)
                w.write(f'{m}:hw2\thw2\t{v}\t{v - t}\t{v + t}\tagree to {"1.5 percent (the transcripts come from Trinity, which gives a slightly different assembly at every run)" if tr else "0.2 percent"}\n')
            for a in ('ctrl_canu', 'ctrl_flye', 'ctrl_canu_quiver', 'ctrl_flye_quiver'):
                if (m, a) in M:
                    v = M[(m, a)]; t = abs(v) * 0.25
                    w.write(f'{m}:{a}\tcontrol\t{v}\t{v - t}\t{v + t}\tagree to 25 percent (single runs of programs that differ from run to run: Flye by up to 12 percent, the polished Canu control by up to 21 percent in the number of unspanned places)\n')
    print('written validation/expected.tsv')
else:
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(res) / '10_validation'; out.mkdir(parents=True, exist_ok=True)
    M, _ = read_measures(res); counts = read_counts(res); ok = bad = miss = 0; lines = []
    for r in csv.DictReader(open(HW / 'validation' / 'expected.tsv'), delimiter='\t'):
        item = r['item']
        if r['group'] == 'counts': v = counts.get(item)
        else:
            m, a = item.split(':')
            if a == 'procedure':
                runs = [M[(m, x)] for x in ('proc_r1', 'proc_r2', 'proc_r3') if (m, x) in M]; v = sum(runs) / len(runs) if runs else None
            else: v = M.get((m, a))
        if v is None: miss += 1; lines.append(f'[MISSING] {item}'); continue
        lo, hi = float(r['low']), float(r['high'])
        if lo - 1e-12 <= v <= hi + 1e-12: ok += 1; lines.append(f'[PASS] {item}: {v:.6g} within {lo:.6g} to {hi:.6g}')
        else: bad += 1; lines.append(f'[FAIL] {item}: {v:.6g} outside {lo:.6g} to {hi:.6g}')
    verdict = 'OVERALL: PASS - the expected table is reproduced' if bad == 0 and miss == 0 else f'OVERALL: FAIL ({bad} outside, {miss} missing)'
    (out / 'validation_report.txt').write_text('\n'.join(lines + ['', f'{ok} pass, {bad} fail, {miss} missing', verdict]) + '\n'); print(verdict, ok, bad, miss)
    sys.exit(0 if bad == 0 and miss == 0 else 1)   # an error code when the results are outside the table (the summary job passes it on)
