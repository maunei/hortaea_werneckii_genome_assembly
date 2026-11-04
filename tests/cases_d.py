from support_d import *
import time, multiprocessing, runpy, urllib.request, fcntl, builtins

def fixture(name):
 r=repo(name);settings(r);exe(r/'bin/squeue','exit 0\n');exe(r/'bin/scancel','echo "$@" >> "$CANCELS"\n');exe(r/'bin/sleep','exit 0\n');return r

def fx35():
 # Instrument only I/O and scheduling, not downloader decisions. The real program runs in each child.
 ctx=multiprocessing.get_context('fork')
 source=HW/'scripts/fetch_archive.py';payload=b'valid archive payload\n';digest=hashlib.md5(payload).hexdigest()
 def worker(man,d,fail,entered,release,attempt,done,hold_report=False):
  realflock=fcntl.flock
  def flock(fd,op):attempt.set();return realflock(fd,op)
  fcntl.flock=flock
  def urlopen(*a,**kw):
   if not hold_report:
    entered.set()
    if release is not None and not release.wait(12):raise RuntimeError('test coordinator did not release download')
   if fail:raise OSError('injected network failure')
   return io.BytesIO(payload)
  original_open=builtins.open
  class ReportReader:
   def __init__(self,f):self.f=f
   def read(self):
    value=self.f.read();self.f.close();entered.set()
    if not release.wait(12):raise RuntimeError('test coordinator did not release report reader')
    return value
  def opening(path,mode='r',*a,**kw):
   f=original_open(path,mode,*a,**kw)
   return ReportReader(f) if hold_report and str(path)==str(d/'fetch_report.tsv') and mode=='r' else f
  builtins.open=opening
  urllib.request.urlopen=urlopen;time.sleep=lambda _:None
  sys.argv=['fetch_archive.py',str(man),str(d),'1']
  try:runpy.run_path(str(source),run_name='__main__')
  except SystemExit as e:done.set();raise SystemExit(e.code)
  finally:done.set()
 def wait_for(pred):
  end=time.monotonic()+12
  while not pred():
   if time.monotonic()>end:raise RuntimeError('downloader did not reach coordinated I/O')
   time.sleep(.01)
 def manifest_at(d,name):
  p=d/(name+'.tsv');write(p,f'run\tname\tsize\tmd5\turl\nR\t{name}\t{len(payload)}\t{digest}\tmocked://archive\n');return p
 for fail in (False,True):
  d=W/('failed-first' if fail else 'two-successes');d.mkdir();write(d/'fetch_report.tsv','history\n')
  names=('data','data') if fail else ('a','b');ma=manifest_at(d,names[0]);mb=manifest_at(d,names[1]);release=ctx.Event();ea=ctx.Event();eb=ctx.Event();aa=ctx.Event();ab=ctx.Event();da=ctx.Event();db=ctx.Event()
  a=ctx.Process(target=worker,args=(ma,d,fail,ea,release,aa,da,not fail));b=ctx.Process(target=worker,args=(mb,d,False,eb,None,ab,db));ps=[a,b]
  try:
   a.start();wait_for(ea.is_set)
   with open(d/'.fetch.lock','a') as probe:
    held=False
    try:fcntl.flock(probe,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.flock(probe,fcntl.LOCK_UN)
    except BlockingIOError:held=True
   check(held,'actual downloader holds destination exclusion '+('while downloading' if fail else 'through report read/replace transaction'))
   b.start();wait_for(lambda:ab.is_set() or db.is_set());release.set()
   for p in ps:p.join(15)
   check([p.exitcode for p in ps]==([1,0] if fail else [0,0]),'both real downloader invocations executed and returned expected statuses')
   check(all((d/'R'/n).is_file() and (d/'R'/n).read_bytes()==payload for n in set(names)),'successful inputs survive both invocations')
   rows=(d/'fetch_report.tsv').read_text().splitlines();check(len(rows)==3 and rows[0]=='history','both downloader report rows survive with previous history')
   if fail:
    ec=ctx.Event();ac=ctx.Event();dc=ctx.Event();c=ctx.Process(target=worker,args=(mb,d,True,ec,None,ac,dc));ps.append(c);c.start();c.join(15)
    check(c.exitcode==0 and not ec.is_set() and (d/'R/data').read_bytes()==payload,'later invocation with broken network reuses installed verified file without deleting it')
  finally:
   release.set()
   for p in ps:
    if p.pid is not None:
     if p.is_alive():p.terminate()
     p.join(3)

def fx36():
 for mode in ('queued','queued_array','finished','unrelated','empty','absent'):
  r=fixture(mode);led=r/'jobs/submitted_by_submit_all.tsv';calls=r/'calls';queries=r/'queries';cancels=r/'cancels'
  if mode not in ('empty','absent'):write(led,'old\t111\t\t01_check_inputs.sbatch\t\n')
  elif mode=='empty':write(led,'')
  exe(r/'bin/squeue','echo "$*" >> "$QUERIES"\nif [[ " $* " != *" -n "* ]]; then case "$CASE" in queued) echo 111;; queued_array) echo "111_[0-4]";; unrelated) [[ " $* " == *" -j "* ]] || echo 222;; esac; fi; exit 0\n')
  exe(r/'bin/sbatch','echo called >> "$CALLS"\necho "$((122 + $(wc -l < "$CALLS")))"\n')
  p=run(['bash',r/'setup_and_run_all.sh','run'],renv(r,CASE=mode,CALLS=calls,QUERIES=queries,CANCELS=cancels,HW_PREPARE_CMD='true'),r);print(mode,p.returncode,p.stdout)
  if mode.startswith('queued'):check(p.returncode!=0 and not calls.exists() and not cancels.exists() and '\t111\t' in led.read_text(),'queued old job refuses actual stage run without truncation, submission, or cancellation')
  else:check(p.returncode==0 and calls.exists() and len(calls.read_text().splitlines())==97 and '\t111\t' not in led.read_text(),'safe '+mode+' ledger permits all actual mocked submissions')
  if mode not in ('empty','absent'):check(queries.exists() and any(' -n ' not in ' '+line+' ' for line in queries.read_text().splitlines()),'previous-attempt queue state was actually queried')

def fx37():
 names=('pacbio_files','rna_sra_files','illumina2013_sra_files','pacbio_deposited_fastq')
 for bad in (None,)+tuple((n,state) for n in names for state in ('missing','empty')):
  label='good' if bad is None else '-'.join(bad);r=fixture(label);write(r/'input/CHECKSUMS.md5','abc  regular\n');write(r/'input/regular','data')
  for n in names:write(r/'input/manifests'/f'{n}.tsv','run\tname\tsize\tmd5\turl\n')
  if bad:
   p=r/'input/manifests'/f'{bad[0]}.tsv'
   if bad[1]=='missing':p.unlink()
   else:p.write_text('')
  exe(r/'bin/sbatch','echo BAD_SUBMISSION >> "$CALLS"; exit 97\n')
  p=run(['bash',r/'setup_and_run_all.sh','inputs'],renv(r,CALLS=r/'calls'),r);print(label,p.returncode,p.stdout)
  check(p.returncode==0 and 'nothing to download' in p.stdout if bad is None else p.returncode!=0 and bad[0]+'.tsv' in p.stdout,'real stage inputs '+('accepts complete manifest inventory' if bad is None else 'rejects '+label))
  check(not (r/'calls').exists(),'manifest precheck neither downloads nor submits')

def fx38():
 r=fixture('grep');s=(r/'scripts/06_fetch_databases.sh').read_text();fn=s[s.index('add_entry() {'):s.index('\n}\n',s.index('add_entry() {'))+3];tab=r/'tab';original='name\tsource\tversion\tdate\tmd5\tuse\nx\told\tv\td\tm\tu\ny\tkeep\tv\td\tm\tu\n';script=write(W/'entry.sh','set -euo pipefail\n'+fn+'\nadd_entry x new v d m u\n');real=shutil.which('grep')
 for mode in ('exists','absent','query-error'):
  (r/'probe').unlink(missing_ok=True)
  write(tab,original if mode!='absent' else original.replace('x\told\tv\td\tm\tu\n',''))
  exe(r/'bin/grep',f'echo "$*" >> "$PROBE"\nif [ "$CASE" = query-error ] && [ "$1" = -q ]; then exit 2; fi\nexec {real} "$@"\n')
  p=run(['bash',script],renv(r,TAB=tab,DBS=r/'db',CASE=mode,PROBE=r/'probe'));print(mode,p.returncode,p.stdout)
  check((r/'probe').exists() and '-q' in (r/'probe').read_text(),'actual initial grep query executed')
  check(p.returncode!=0 and tab.read_text()==original if mode=='query-error' else p.returncode==0 and tab.read_text().count('x\tnew')==1 and 'y\tkeep' in tab.read_text(),'query error preserves table and fails' if mode=='query-error' else mode+' query updates provenance correctly')

def fx39():
 r=fixture('depth');bin=r/'environments/04_I_qc/bin';bin.mkdir(parents=True);fa=write(r/'a.fa','>a\nACGT\n');reads=write(r/'reads.fq','@r\nACGT\n+\nIIII\n')
 exe(bin/'minimap2','echo SAM\n');exe(bin/'samtools','if [ "$1" = sort ]; then cat >/dev/null; while [ "$1" != -o ]; do shift; done; echo bam > "$2"; fi; exit 0\n');exe(bin/'mosdepth','args=("$@"); prefix="${args[${#args[@]}-2]}"; printf "chrom\\tlength\\tbases\\tmean\\na\\t4\\t16\\t4\\n" > "$prefix.mosdepth.summary.txt"\n')
 realawk=shutil.which('awk');realmv=shutil.which('mv')
 exe(r/'bin/awk',f'echo "$1" >> "$AWK_PROBE"\nif [ "$CASE" = first ] && [[ "$1" == /^* ]]; then exit 37; fi\nif [ "$CASE" = second ] && [[ "$1" == BEGIN* ]]; then exit 38; fi\nexec {realawk} "$@"\n')
 exe(r/'bin/mv',f'echo ran >> "$MV_PROBE"\n[ "$CASE" != rename ] || exit 39\nexec {realmv} "$@"\n')
 for mode in ('good','first','second','rename'):
  for probe in ('awk-probe','mv-probe'):(r/probe).unlink(missing_ok=True)
  d=r/'work'/mode;p=run(['bash',r/'scripts/07_depth.sh','a',fa,reads,'1'],renv(r,DEPTH_DIR=d,FORCE='1',CASE=mode,AWK_PROBE=r/'awk-probe',MV_PROBE=r/'mv-probe'));print(mode,p.returncode,p.stdout)
  check((r/'awk-probe').exists(),'actual depth awk stage ran')
  check(p.returncode==0 and (d/'depth.per_contig.tsv').read_text().splitlines()[-1]=='a\t4\t4\t4' if mode=='good' else p.returncode!=0 and not (d/'depth.per_contig.tsv').exists(),'valid depth table computed' if mode=='good' else mode+' depth-table failure propagates')
  if mode=='second':check('BEGIN' in (r/'awk-probe').read_text(),'second awk actually attempted')
  if mode=='rename':check((r/'mv-probe').exists(),'final rename actually attempted')

def fx40():
 # Sixth assigned item: successful newer prerequisite must bypass a stale marker.
 if os.geteuid()==0:raise RuntimeError('unremovable marker injection requires an unprivileged user')
 r=fixture('freshness');s=(r/'jobs/06_tests.sbatch').read_text();fn=s[s.index('step() {'):s.index('\ns_contiguity()')]
 for stale in (False,True):
  d=W/('stale' if stale else 'fresh');(d/'steps').mkdir(parents=True)
  for n,t in [('producer',200 if stale else 100),('consumer',150)]:p=write(d/'steps'/f'{n}.done','old');os.utime(p,(t,t))
  (d/'steps').chmod(0o555)
  try:p=run(['bash','-c',fn+'\nconsumer() { echo ran > "$BIG/ran"; }\nstep consumer consumer producer\nprintf "%s" "$FAILED" > "$BIG/failed"\n'],renv(r,BIG=d,FORCE='0',FAILED=''));print(stale,p.returncode,p.stdout)
  finally:(d/'steps').chmod(0o755)
  check((d/'steps/consumer.done').exists(),'existing consumer marker remained available despite denied unlink')
  check((d/'ran').exists() if stale else not (d/'ran').exists(),'newer prerequisite reruns consumer despite unremovable marker' if stale else 'fresh completed consumer is still skipped')
  check(not (d/'failed').read_text(),'successful or reused consumer is not marked failed')

globals()[sys.argv[1]]();finish()
