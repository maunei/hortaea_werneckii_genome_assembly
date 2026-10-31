#!/usr/bin/env python3
"""Step 10: how close is a rerun to the first analysis?
  python scripts/10_validate.py make-expected RESULTS_DIR      writes validation/expected.tsv from the results of the run reported in the README
  python scripts/10_validate.py check RESULTS_DIR [OUT]        compares the results of a rerun with validation/expected.tsv and writes a report
Nothing is judged as pass or fail and the exit code is always 0: for every value the report gives the value of the rerun, the value of the first analysis,
the difference in percent and a note, "within the usual variation" or "larger than usual". The usual variation of a measure of the procedure (runs proc_r1 to proc_r3) is
the range seen over the three runs of the reported run, widened on both sides by that range or by 0.5 percent of the mean, whichever is larger; a measure of Hw 2.0, which
does not depend on any assembler, 0.2 percent; the transcript measures (Trinity differs at every run) 1.5 percent; the measures that use the Swiss-Prot proteins, which
UniProt changes from month to month, 1 percent; the control assemblies (single runs of Flye and Canu) 25 percent. The numbers of reads and the checksum of the sequences of
the assembly are compared exactly and reported as "same" or "differs".
Files: validation_report.txt (readable) and closeness.tsv (the same values as a table) in OUT (default RESULTS_DIR/10_validation)."""
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
def read_seq_md5(res):   # checksum of the sequences of the final assembly of each run of the procedure (names and orientation ignored), from step 09
    c = {}
    f = Path(res) / '09_summary' / 'replicate_check.tsv'
    if f.exists():
        for r in csv.DictReader(open(f), delimiter='\t'):
            if r.get('polished_assembly_sequences_md5'): c[r['run']] = r['polished_assembly_sequences_md5']
    return c
mode = sys.argv[1]; res = sys.argv[2]
if mode == 'make-expected':
    M, assemblies = read_measures(res); counts = read_counts(res)
    meas = sorted({k[0] for k in M})
    with open(HW / 'validation' / 'expected.tsv', 'w') as w:
        w.write('item\tgroup\texpected\tlow\thigh\trule\n')
        for k, v in counts.items(): w.write(f'{k}\tcounts\t{v}\t{v}\t{v}\texact\n')
        for k, v in sorted(read_seq_md5(res).items()): w.write(f'assembly_sequences_md5:{k}\tchecksum\t{v}\t{v}\t{v}\texact (md5 of the sequences of the final assembly, names and orientation ignored)\n')
        for m in meas:
            runs = [M[(m, a)] for a in ('proc_r1', 'proc_r2', 'proc_r3') if (m, a) in M]
            if runs:
                lo, hi = min(runs), max(runs); mean = sum(runs) / len(runs); tr = (m == 'transcripts'); sp = (m == 'proteins_whole'); n = 0.015 * abs(mean) if tr else (max(hi - lo, 0.01 * abs(mean)) if sp else max(hi - lo, 0.005 * abs(mean)))
                rule = 'inside the range of the runs widened by 1.5 percent of the mean (the transcripts come from Trinity, which gives a slightly different assembly at every run: 0.5 and 0.6 percent in two reruns)' if tr else ('inside the range of the runs widened by 1 percent of the mean (the proteins come from Swiss-Prot, which UniProt changes from month to month)' if sp else 'inside the range of the runs widened by the range or by 0.5 percent of the mean (the larger)')
                w.write(f'{m}:procedure\tprocedure\t{mean}\t{lo - n}\t{hi + n}\t{rule}\n')
            if (m, 'hw2') in M:
                v = M[(m, 'hw2')]; tr = (m == 'transcripts'); sp = (m == 'proteins_whole'); t = abs(v) * (0.015 if tr else (0.01 if sp else 0.002))
                w.write(f'{m}:hw2\thw2\t{v}\t{v - t}\t{v + t}\tagree to {"1.5 percent (the transcripts come from Trinity, which gives a slightly different assembly at every run)" if tr else ("1 percent (the proteins come from Swiss-Prot, which UniProt changes from month to month)" if sp else "0.2 percent")}\n')
            for a in ('ctrl_canu', 'ctrl_flye', 'ctrl_canu_quiver', 'ctrl_flye_quiver'):
                if (m, a) in M:
                    v = M[(m, a)]; t = abs(v) * 0.25
                    w.write(f'{m}:{a}\tcontrol\t{v}\t{v - t}\t{v + t}\tagree to 25 percent (single runs of programs that differ from run to run: Flye by up to 12 percent, the polished Canu control by up to 21 percent in the number of unspanned places)\n')
    print('written validation/expected.tsv')
else:
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(res) / '10_validation'; out.mkdir(parents=True, exist_ok=True)
    M, _ = read_measures(res); counts = read_counts(res); SEQ = read_seq_md5(res)
    rows = []; lines = []; n_in = n_out = n_na = 0; asm_same = []; cnt_same = []
    for r in csv.DictReader(open(HW / 'validation' / 'expected.tsv'), delimiter='\t'):
        item = r['item']; first = float(r['expected']) if r['group'] != 'checksum' else r['expected']
        if r['group'] == 'checksum':
            v = SEQ.get(item.split(':')[1])
            if v is None: n_na += 1; lines.append(f'[not available] {item}'); rows.append((item, r['group'], '', first, '', '', '', 'not available')); continue
            same = (v == first); asm_same.append(same)
            lines.append(f'[{"same" if same else "differs"}] {item}: {v} ({"identical to" if same else "different from"} the checksum of the first analysis, {first})')
            rows.append((item, r['group'], v, first, '', '', '', 'same' if same else 'differs')); continue
        if r['group'] == 'counts': v = counts.get(item)
        else:
            m, a = item.split(':')
            if a == 'procedure':
                runs = [M[(m, x)] for x in ('proc_r1', 'proc_r2', 'proc_r3') if (m, x) in M]; v = sum(runs) / len(runs) if runs else None
            else: v = M.get((m, a))
        if v is None: n_na += 1; lines.append(f'[not available] {item}'); rows.append((item, r['group'], '', first, '', '', '', 'not available')); continue
        diff = 100 * (v - first) / first if first else 0.0
        if r['group'] == 'counts':
            same = abs(v - first) < 1e-9; cnt_same.append(same)
            lines.append(f'[{"same" if same else "differs"}] {item}: {v:.6g}; first analysis {first:.6g}'); rows.append((item, r['group'], v, first, f'{diff:+.3f}', '', '', 'same' if same else 'differs')); continue
        lo, hi = float(r['low']), float(r['high']); inside = lo - 1e-12 <= v <= hi + 1e-12
        n_in += inside; n_out += (not inside)
        note = 'within the usual variation' if inside else 'larger than usual'
        lines.append(f'[{"close" if inside else "larger than usual"}] {item}: {v:.6g}; first analysis {first:.6g}; difference {diff:+.3f} percent; usual variation {lo:.6g} to {hi:.6g}')
        rows.append((item, r['group'], v, first, f'{diff:+.3f}', lo, hi, note))
    tot = n_in + n_out
    summ = [f'{n_in} of {tot} values are within the usual variation of the first analysis' + (f'; {n_out} {"value is" if n_out == 1 else "values are"} larger than usual (the data or the programs used differ from the first analysis: see the lines marked "larger than usual")' if n_out else '') + '.']
    if asm_same: summ.append('The sequences of the assembly are ' + ('identical to those of the first analysis (same checksum) in every run of the procedure.' if all(asm_same) else 'different from those of the first analysis (different checksum): the program versions or the data differ.'))
    if cnt_same: summ.append('The numbers of reads are ' + ('the same as in the first analysis.' if all(cnt_same) else 'different from the first analysis.'))
    if n_na: summ.append(f'{n_na} values are not available (the steps that make them have not been run).')
    (out / 'validation_report.txt').write_text('\n'.join(summ + [''] + lines) + '\n')
    with open(out / 'closeness.tsv', 'w') as w:
        w.write('item\tgroup\tthis_run\tfirst_analysis\tdifference_percent\tusual_low\tusual_high\tnote\n')
        for x in rows: w.write('\t'.join(str(y) for y in x) + '\n')
    print('\n'.join(summ))
    sys.exit(0)   # the comparison is a report: it never makes the run FAILED
