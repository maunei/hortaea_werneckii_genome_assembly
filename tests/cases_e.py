from support_e import *
import fcntl,time

def fx50():
 if os.geteuid()==0:raise RuntimeError('permission injection requires non-root')
 source=write(W/'source','valid payload\n');r=repo();d,m=fetch(r,'dest',source)
 for mode in ('good','open-failure','flock-failure'):
  dest=W/mode;dest.mkdir();(dest/'R').mkdir();write(dest/'R/data','old invalid data');write(dest/'R/data.md5ok','old marker');write(dest/'R/data.active.part','unfinished');write(dest/'fetch_report.tsv','history\n');write(dest/'.fetch.lock','')
  before={p.relative_to(dest):p.read_bytes() for p in dest.rglob('*') if p.is_file()}
  if mode=='open-failure':(dest/'.fetch.lock').chmod(0o444)
  if mode=='flock-failure':
   runner=write(W/'runner.py','import fcntl,runpy,sys\ndef bad(*a,**kw):raise OSError("injected lock failure")\nfcntl.flock=bad\nsys.argv=sys.argv[1:]\nrunpy.run_path(sys.argv[0],run_name="__main__")\n');args=['python3','-S',runner,r/'scripts/fetch_archive.py',m,dest,'1']
  else:args=['python3','-S',r/'scripts/fetch_archive.py',m,dest,'1']
  p=run(args,renv(r));print(mode,p.returncode,p.stdout)
  if mode=='good':check(p.returncode==0 and (dest/'R/data').read_bytes()==source.read_bytes(),'valid lock permits actual local download')
  else:
   after={p.relative_to(dest):p.read_bytes() for p in dest.rglob('*') if p.is_file()}
   check(p.returncode==2 and 'lock' in p.stdout and before==after,'failed '+mode+' exits 2 without changing data, marker, part or report')

def fx51():
 def fixture(name):
  r=repo(name);settings(r);exe(r/'bin/squeue','if [[ " $* " != *" -n "* ]] && [ "${QUEUE_FAIL:-}" = yes ]; then echo outage >&2; exit 17; fi\n');exe(r/'bin/scancel','echo "$*" >> "$CANCELS"\n');exe(r/'bin/sbatch','if [ "${HOLD:-}" = yes ]; then touch "$ENTERED"; while [ ! -e "$RELEASE" ]; do sleep .01; done; fi\necho called >> "$CALLS"; echo "$((122 + $(wc -l < "$CALLS")))"\n');return r
 r=fixture('queue');led=write(r/'jobs/submitted_by_submit_all.tsv','old\t111\t\t01_check_inputs.sbatch\t\n');before=led.read_bytes();e=renv(r,HW_PREPARE_CMD='true',QUEUE_FAIL='yes',CALLS=r/'calls',CANCELS=r/'cancels');p=run(['bash',r/'setup_and_run_all.sh','run'],e,r);print('queue outage',p.returncode,p.stdout);check(p.returncode!=0 and led.read_bytes()==before and not (r/'calls').exists() and not (r/'cancels').exists(),'queue failure preserves ledger and prevents submission/cancellation')
 r=fixture('overlap');e=renv(r,HW_PREPARE_CMD='true',CALLS=r/'calls',CANCELS=r/'cancels',ENTERED=r/'entered',RELEASE=r/'release');a=subprocess.Popen(['bash',str(r/'setup_and_run_all.sh'),'run'],cwd=r,env=dict(e,HOLD='yes'),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 try:
  end=time.monotonic()+12
  while not (r/'entered').exists():
   if time.monotonic()>end:raise RuntimeError('first submitter never reached sbatch')
   time.sleep(.01)
  b=run(['bash',r/'setup_and_run_all.sh','run'],e,r);print('second',b.returncode,b.stdout)
  check(b.returncode!=0 and not (r/'calls').exists() and not (r/'cancels').exists(),'second stage run refuses while first actually holds submission lock')
  write(r/'release','yes');output=a.communicate(timeout=120)[0];check(a.returncode==0 and len((r/'calls').read_text().splitlines())==97,'first submitter finishes its actual mocked submissions')
  (r/'calls').unlink();p=run(['bash',r/'setup_and_run_all.sh','run'],e,r);check(p.returncode==0 and len((r/'calls').read_text().splitlines())==97,'lock is released when first stage-run process exits')
 finally:
  write(r/'release','yes')
  if a.poll() is None:a.terminate()
  a.communicate(timeout=5)

def fx52():
 r=repo();s=(r/'jobs/01_fetch_inputs.sbatch').read_text();start=s.index('fetch_ncbi() {');fn=s[start:s.index('\n}\n',start)+3];script=write(W/'ncbi.sh',fn+'\nfetch_ncbi "$DEST" mocked://ncbi\n');d=W/'ncbi';d.mkdir();real=shutil.which('flock')
 exe(r/'bin/flock',f'touch "$ATTEMPT"\nexec {real} "$@"\n')
 exe(r/'bin/curl','while [ "$1" != -o ]; do shift; done; echo payload > "$2"\nif [ "$ACTOR" = A ]; then echo "$2" > "$ENTERED"; while [ ! -e "$RELEASE" ]; do sleep .01; done; fi\n[ "${CURL_FAIL:-}" != yes ] || exit 22\n')
 e=renv(r,DEST=d/'data',ENTERED=W/'entered',RELEASE=W/'release');a=subprocess.Popen(['bash',str(script)],env=dict(e,ACTOR='A',ATTEMPT=str(W/'attempt-A')),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);b=None
 try:
  end=time.monotonic()+12
  while not (W/'entered').exists():
   if time.monotonic()>end:raise RuntimeError('first curl did not run')
   time.sleep(.01)
  part=Path((W/'entered').read_text().strip());b=subprocess.Popen(['bash',str(script)],env=dict(e,ACTOR='B',ATTEMPT=str(W/'attempt-B')),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  end=time.monotonic()+12
  while b.poll() is None and not (W/'attempt-B').exists():
   if time.monotonic()>end:raise RuntimeError('second fetch made no progress')
   time.sleep(.01)
  check(part.exists(),'second fetch preserves the active first temporary file')
  write(W/'release','yes');ao=a.communicate(timeout=120)[0];bo=b.communicate(timeout=120)[0];print('first',a.returncode,ao,'second',b.returncode,bo);check(a.returncode==0 and b.returncode==0 and (d/'data').read_text()=='payload\n','both fetches succeed and retain installed input')
  p=run(['bash',script],dict(e,ACTOR='B',ATTEMPT=W/'attempt-B',DEST=d/'bad',CURL_FAIL='yes'));check(p.returncode==6 and not (d/'bad').exists(),'download failure remains fatal after locking')
 finally:
  write(W/'release','yes')
  for p in (a,b):
   if p is not None:
    if p.poll() is None:p.terminate()
    p.communicate(timeout=5)

globals()[sys.argv[1]]();finish()
