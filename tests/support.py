"""Standard-library helpers for isolated, offline FX regression tests."""
import os, sys, subprocess, shutil, json, hashlib, gzip, csv, io
from pathlib import Path
HW=Path(os.environ['FX_HW']).resolve(); W=Path(os.environ['FX_W']).resolve()
errors=[]
def check(ok,message):
    print(('ok: ' if ok else 'FAIL: ')+message, flush=True)
    if not ok: errors.append(message)
def finish():
    if errors: print(f'{len(errors)} regression assertion(s) failed',file=sys.stderr);raise SystemExit(1)
    print('PASS');raise SystemExit(0)
def write(p,s,executable=False):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
    if executable:p.chmod(0o755)
    return p
def exe(p,s): return write(p,'#!/bin/bash\n'+s,True)
def pyexe(p,s):return write(p,'#!/usr/bin/env python3\n'+s,True)
def env(**kw):
    e=os.environ.copy()
    for k in list(e):
        if k.startswith(('HW_','SLURM_')) or k in ('HW','RESULTS','WORK','ENVS','DBS','INPUT','LOGS_BASE','LEDGER','DRYRUN','CHECK','FORCE','PY','ASM','FASTA','READS','THREADS','R1','R2','MAMBA','OUT','OUTDIR','MAPDIR','OUTNAME','RAW','READS_TAG','RES_OUT','BIG_OUT','PB_READS','RNA_DIR','RNA_RUN','RUN','GROUP','NEEDED','EXPECTED','DEPTH_DIR','PYTHONPATH','PYTHONHOME'):e.pop(k,None)
    e.update(PYTHONDONTWRITEBYTECODE='1',TMPDIR=str(W),MPLCONFIGDIR=str(W/'mpl'))
    e.update({k:str(v) for k,v in kw.items()});return e
def run(args,e=None,cwd=None,timeout=15):
    try:return subprocess.run([str(a) for a in args],env=e or env(),cwd=cwd or W,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
    except subprocess.TimeoutExpired as ex:raise RuntimeError('test command exceeded offline timeout: '+str(args)) from ex

def repo(name='repo'):
    r=W/name;r.mkdir()
    for d in ('scripts','config','jobs','tests','validation'):
        if (HW/d).exists():shutil.copytree(HW/d,r/d)
    shutil.copyfile(HW/'setup_and_run_all.sh',r/'setup_and_run_all.sh')
    (r/'config/local.sh').unlink(missing_ok=True)
    for d in ('input','logs','results','bin'):(r/d).mkdir(exist_ok=True)
    for cmd in ('sbatch','sacct','scancel','squeue','curl','git','scontrol'):
        exe(r/'bin'/cmd,'echo "UNCONFIGURED MOCK '+cmd+'" >&2; exit 97\n')
    return r

def renv(r,**kw):
    e=env(HW=r,HW_WORK=r/'work',HW_ENVS=r/'environments',HW_DBS=r/'db',HW_ACCOUNT='test',HW_MAIL_WHEN='NONE',PATH=str(r/'bin')+':'+os.environ['PATH'],SLURM_SUBMIT_DIR=r)
    e.update({k:str(v) for k,v in kw.items()});return e

def settings(r,extra=''):
    write(r/'settings.yaml',f'account: test\nmail_when: NONE\nmodules: # empty\nwork_dir: {r}/work\nenvs_dir: {r}/environments\ndbs_dir: {r}/db\n'+extra)
    p=run(['bash',r/'setup_and_run_all.sh','settings'],renv(r),r)
    if p.returncode:raise RuntimeError('settings positive fixture failed: '+p.stdout)

def setup_defs(r):
    s=(r/'setup_and_run_all.sh').read_text();mark='\ncase "$STAGE" in'
    if mark not in s:raise RuntimeError('cannot locate setup dispatcher; adapt extraction')
    return write(r/'setup_defs.sh',s.split(mark)[0])

def manifest(path,source,md5=None,size=None):
    data=source.read_bytes();digest=md5 or hashlib.md5(data).hexdigest()
    write(path,'run\tname\tsize\tmd5\turl\nR\tdata\t'+str(len(data) if size is None else size)+'\t'+digest+'\t'+source.as_uri()+'\n')
    return digest

def fetch(r,folder,source,md5=None):
    dest=W/folder;dest.mkdir(exist_ok=True);(dest/'R').mkdir(exist_ok=True);m=dest/'manifest.tsv';manifest(m,source,md5)
    return dest,m

def dofetch(r,d,m):return run(['python3','-S',r/'scripts/fetch_archive.py',m,d,'1'],renv(r))
