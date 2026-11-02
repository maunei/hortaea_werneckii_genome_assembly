#!/usr/bin/env python3
"""Step 09: time and memory of every job. Reads the ledger jobs/submitted.tsv (name, job number, dependency), asks the scheduler (sacct) for wall time, CPU time and
peak memory, and reads the /usr/bin/time records of the long stages (procedure, polishing, controls) from logs/<jobid>_*/*.time.
Output: results/09_summary/resources_jobs.tsv (one row per job), resources_stages.tsv (one row per timed stage), resources_totals.json (core-hours by group).
Run:  HW=$PWD python3 scripts/09_resources.py"""
import os, re, csv, json, subprocess, glob
from pathlib import Path
HW = Path(os.environ.get('HW', Path(__file__).resolve().parent.parent)); out = HW / 'results' / '09_summary'; out.mkdir(parents=True, exist_ok=True)
def secs(t):
    t = t.strip(); d = 0
    if '-' in t: d, t = t.split('-'); d = int(d)
    p = [float(x) for x in t.split(':')]
    while len(p) < 3: p.insert(0, 0.0)
    return d * 86400 + p[0] * 3600 + p[1] * 60 + p[2]
def rss_gb(s):
    m = re.match(r'([\d.]+)([KMGT]?)', s or '')
    if not m or not m.group(1): return None
    return float(m.group(1)) * {'': 1 / 1024 ** 2, 'K': 1 / 1024 ** 2, 'M': 1 / 1024, 'G': 1, 'T': 1024}[m.group(2)]
LED = Path(os.environ['LEDGER']) if os.environ.get('LEDGER') else (HW / 'jobs' / 'submitted_by_submit_all.tsv' if (HW / 'jobs' / 'submitted_by_submit_all.tsv').exists() and (HW / 'jobs' / 'submitted_by_submit_all.tsv').stat().st_size > 0 else HW / 'jobs' / 'submitted.tsv')
ledger = [l.rstrip('\n').split('\t') for l in open(LED) if l.strip()]
ids = [r[1] for r in ledger if len(r) > 1 and r[1].isdigit()]
txt = subprocess.run(['sacct', '-j', ','.join(ids), '--parsable2', '--noheader', '-o', 'JobID,State,Elapsed,TotalCPU,AllocCPUS,MaxRSS'], capture_output=True, text=True).stdout
tasks = {}
for l in txt.splitlines():
    if not l.strip(): continue
    jid, st, el, tc, nc, mr = l.split('|')
    task_id = jid.split('.')[0]
    t = tasks.setdefault(task_id, {'state': '', 'wall': 0.0, 'cpu': 0.0, 'ncpu': 0, 'rss': 0.0})
    if jid == task_id:
        t.update(state=st.split()[0], wall=secs(el), cpu=secs(tc) if tc else 0.0, ncpu=int(nc) if nc.isdigit() else 0)
    else:
        g = rss_gb(mr)
        if g: t['rss'] = max(t['rss'], g)
jobs = {}
for task_id, t in tasks.items():
    root = task_id.split('_')[0]
    j = jobs.setdefault(root, {'states': [], 'wall': 0.0, 'cpu': 0.0, 'ncpu': 0, 'rss': 0.0})
    if t['state']: j['states'].append(t['state'])
    j['wall'] = max(j['wall'], t['wall'])
    j['cpu'] += t['cpu']
    j['ncpu'] = max(j['ncpu'], t['ncpu'])
    j['rss'] = max(j['rss'], t['rss'])
for j in jobs.values():
    sts = j.pop('states')
    j['state'] = 'COMPLETED' if (sts and all(s == 'COMPLETED' for s in sts)) else (sts[0] if sts else 'UNKNOWN')
def group(n):
    if n.startswith('05_') and 'ctrl' in n: return 'controls'
    for k, g in (('01_', 'preparation'), ('02_', 'preparation'), ('03_', 'preparation'), ('04_procedure', 'procedure'), ('05_', 'procedure'), ('04_control', 'controls'), ('06_', 'tests'), ('07_', 'tests'), ('08_', 'tests')):
        if n.startswith(k): return g
    return 'other'
rows = []; tot = {}
with open(out / 'resources_jobs.tsv', 'w') as w:
    w.write('job\tjobid\tstate\twall_h\tcpu_core_h\tallocated_cpus\tpeak_memory_gb\n')
    for r in ledger:
        if len(r) < 2 or r[1] not in jobs: continue
        j = jobs[r[1]]; w.write(f"{r[0]}\t{r[1]}\t{j['state']}\t{j['wall']/3600:.2f}\t{j['cpu']/3600:.1f}\t{j['ncpu']}\t{j['rss']:.1f}\n")
        g = group(r[3] if len(r) > 3 else r[0])
        if j['state'] == 'COMPLETED': tot[g] = tot.get(g, 0) + j['cpu'] / 3600
id_set = set(ids)
with open(out / 'resources_stages.tsv', 'w') as w:
    w.write('jobid\tstage\twall_h\tpeak_memory_gb\n')
    for f in sorted(glob.glob(str(HW / 'logs' / '*' / '*.time'))):
        jid_prefix = Path(f).parent.name.split('_')[0]
        if id_set and jid_prefix not in id_set: continue
        s = open(f).read(); e = re.search(r'Elapsed \(wall clock\) time.*?: ([\d:.]+)', s); m = re.search(r'Maximum resident set size \(kbytes\): (\d+)', s)
        if e and m: w.write(f"{jid_prefix}\t{Path(f).stem}\t{secs(e.group(1))/3600:.2f}\t{int(m.group(1))/1024**2:.1f}\n")
tot['total'] = sum(tot.values()); json.dump({k: round(v, 1) for k, v in tot.items()}, open(out / 'resources_totals.json', 'w'), indent=1); print(tot)
