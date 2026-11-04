#!/usr/bin/env python3
"""Step 09: time and memory of every job. Reads the ledger jobs/submitted.tsv (name, job number, dependency), asks the scheduler (sacct) for wall time, CPU time and
peak memory, and reads the /usr/bin/time records of the long stages (procedure, polishing, controls) from logs/<jobid>_*/*.time.
Output: results/09_summary/resources_jobs.tsv (one row per job), resources_stages.tsv (one row per timed stage), resources_totals.json (core-hours by group).
Run:  HW=$PWD python3 scripts/09_resources.py"""
import os, re, csv, json, subprocess, glob, sys
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
ledger_ids = set(ids)
if not ids: sys.exit('09_resources: the ledger holds no job number')
sa = subprocess.run(['sacct', '-j', ','.join(ids), '--parsable2', '--noheader', '-o', 'JobID,JobIDRaw,State,Elapsed,TotalCPU,AllocCPUS,MaxRSS'], capture_output=True, text=True)
if sa.returncode != 0 or not sa.stdout.strip():   # no accounting is not a table of zeros
    sys.exit(f'09_resources: sacct failed or returned nothing (exit {sa.returncode}): the table of resources was not made')
txt = sa.stdout
tasks = {}; rawroot = {}   # tasks: one entry per job or array task; rawroot: the raw job number of an array task -> the job number of the ledger
for l in txt.splitlines():
    if not l.strip(): continue
    jid, raw, st, el, tc, nc, mr = l.split('|')
    task_id = jid.split('.')[0]; root = task_id.split('_')[0]
    t = tasks.setdefault(task_id, {'state': '', 'wall': 0.0, 'cpu': 0.0, 'ncpu': 0, 'rss': 0.0, 'root': root})
    rawroot[raw.split('.')[0]] = root
    if jid == task_id:
        t.update(state=st.split()[0], wall=secs(el), cpu=secs(tc) if tc else 0.0, ncpu=int(nc) if nc.isdigit() else 0)
    else:
        g = rss_gb(mr)
        if g: t['rss'] = max(t['rss'], g)
missing = sorted(i for i in ids if i not in {t['root'] for t in tasks.values()})
if missing: sys.exit('09_resources: the accounting has no record of job(s) ' + ', '.join(missing) + ': the table of resources was not made')
def task_numbers(r):   # the numbers of the tasks of the job that the ledger line declares (the array of the line or of the header of the job file); None for a job without array
    spec = ''
    m = re.search(r'--array[= ](\S+)', r[4] if len(r) > 4 else '')
    if m: spec = m.group(1)
    else:
        try:
            for line in open(HW / 'jobs' / r[3]):
                m = re.match(r'#SBATCH\s+--array=(\S+)', line)
                if m: spec = m.group(1); break
        except (OSError, IndexError): pass
    nums = set()
    for part in re.sub(r'%\d+', '', spec).split(','):
        m = re.fullmatch(r'(\d+)-(\d+)(?::(\d+))?', part)
        if m: nums |= set(range(int(m.group(1)), int(m.group(2)) + 1, int(m.group(3) or 1)))
        elif part.isdigit(): nums.add(int(part))
    return nums or None
short = []
for r in ledger:
    if len(r) > 1 and r[1].isdigit():
        want = task_numbers(r)
        if any('[' in k for k, t in tasks.items() if t['root'] == r[1]):
            short.append(f'{r[1]} (unexpanded array range in accounting)'); continue
        got = {k.split('_', 1)[1] for k, t in tasks.items() if t['root'] == r[1] and '_' in k and '[' not in k}   # the task numbers of the accounting (the allocation row of the job itself has none)
        if want is None: continue
        if got != {str(x) for x in want}: short.append(f'{r[1]} (tasks {sorted(got, key=lambda x: int(x) if x.isdigit() else -1)}, declared {sorted(want)})')
if short: sys.exit('09_resources: the accounting does not hold exactly the tasks of job(s) ' + ', '.join(short) + ': the table of resources was not made')
jobs = {}
for task_id, t in tasks.items():
    root = t['root']
    j = jobs.setdefault(root, {'states': [], 'wall': 0.0, 'cpu': 0.0, 'ncpu': 0, 'rss': 0.0})
    j['states'].append(t['state'] or 'UNKNOWN')
    j['wall'] = max(j['wall'], t['wall'])
    j['cpu'] += t['cpu']
    j['ncpu'] = max(j['ncpu'], t['ncpu'])
    j['rss'] = max(j['rss'], t['rss'])
for j in jobs.values():
    sts = j.pop('states'); bad = [x for x in sts if x != 'COMPLETED']
    j['state'] = bad[0] if bad else 'COMPLETED'   # one task that did not complete: the job did not complete, whatever the order of the tasks
def group(script, key=''):
    if script.startswith('05_') and 'ctrl' in key: return 'controls'   # alignment, polishing and contig removal of the control assemblies use the same job files as the procedure: the key of the ledger tells them apart
    for k, g in (('01_', 'preparation'), ('02_', 'preparation'), ('03_', 'preparation'), ('04_procedure', 'procedure'), ('05_', 'procedure'), ('04_control', 'controls'), ('06_', 'tests'), ('07_', 'tests'), ('08_', 'tests')):
        if script.startswith(k): return g
    return 'other'
rows = []; tot = {}
with open(out / 'resources_jobs.tsv', 'w') as w:
    w.write('job\tjobid\tstate\twall_h\tcpu_core_h\tallocated_cpus\tpeak_memory_gb\n')
    for r in ledger:
        if len(r) < 2 or r[1] not in jobs: continue
        j = jobs[r[1]]; w.write(f"{r[0]}\t{r[1]}\t{j['state']}\t{j['wall']/3600:.2f}\t{j['cpu']/3600:.1f}\t{j['ncpu']}\t{j['rss']:.1f}\n")
        g = group(r[3] if len(r) > 3 else r[0], r[0])
        if j['state'] == 'COMPLETED': tot[g] = tot.get(g, 0) + j['cpu'] / 3600
with open(out / 'resources_stages.tsv', 'w') as w:
    w.write('jobid\tstage\twall_h\tpeak_memory_gb\ttask_job\n')
    for f in sorted(glob.glob(str(HW / 'logs' / '*' / '*.time'))):
        prefix = Path(f).parent.name.split('_')[0]   # the number in the name of the log folder is the number of the job or of the array task
        root = prefix if prefix in ledger_ids else rawroot.get(prefix)
        if root is None: continue   # a log of a job that is not in this ledger (an earlier run)
        s = open(f).read(); e = re.search(r'Elapsed \(wall clock\) time.*?: ([\d:.]+)', s); m = re.search(r'Maximum resident set size \(kbytes\): (\d+)', s)
        if e and m: w.write(f"{root}\t{Path(f).stem}\t{secs(e.group(1))/3600:.2f}\t{int(m.group(1))/1024**2:.1f}\t{prefix}\n")
tot['total'] = sum(tot.values()); json.dump({k: round(v, 1) for k, v in tot.items()}, open(out / 'resources_totals.json', 'w'), indent=1); print(tot)
