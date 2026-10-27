"""Step 06: gathers the measures of one assembly into summary.json (fixed key names, documented in docs/step_06_tests.md) and summary.tsv (the same numbers, one key per row).
Usage: 06_collect.py RES_DIR ASM PACBIO_READS RNA_RUN [FAILED_STEPS]
A measure whose file is missing is stored as null, and the key steps_failed lists the steps that did not finish.
"""
import sys, json, os
res, asm, pb, rna = sys.argv[1:5]
failed = sys.argv[5].split() if len(sys.argv) > 5 and sys.argv[5].strip() else []
def load(n):
    p = os.path.join(res, n)
    return json.load(open(p)) if os.path.exists(p) else None
ct, bu, st, mp, rb, dp, rd, te = (load(x) for x in ('contiguity.json', 'busco.json', 'star.json', 'miniprot.json', 'readback.json', 'depth.json', 'redundancy.json', 'telomeres.json'))
S = dict(
    assembly=asm,
    inputs=dict(pacbio_reads_file=os.path.basename(pb), pacbio_reads=rb['reads_total'] if rb else None, rna_run=rna, rna_pairs=st['input_pairs'] if st else None),
    contiguity=ct, busco=bu, star=st, miniprot=mp, readback=rb, depth=dp, redundancy=rd, telomeres=te,
    steps_failed=failed)
json.dump(S, open(os.path.join(res, 'summary.json'), 'w'), indent=1)
def flat(d, p=''):
    for k, v in d.items():
        if isinstance(v, dict): yield from flat(v, p + k + '.')
        elif isinstance(v, list): yield p + k, ','.join(map(str, v))
        else: yield p + k, v
with open(os.path.join(res, 'summary.tsv'), 'w') as o:
    o.write('key\tvalue\n')
    for k, v in flat(S): o.write(f'{k}\t{"NA" if v is None else v}\n')
