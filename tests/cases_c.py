from support_c import *
def fixture(name):
 r=repo(name); settings(r); exe(r/'bin/squeue','exit 0\n');exe(r/'bin/scancel','echo "$@" >> "$CANCELS"\n');exe(r/'bin/sleep','exit 0\n'); return r

def fx24():
 if os.geteuid()==0: raise RuntimeError('permission injection requires an unprivileged user')
 for case in ('good','stale','append'):
  r=fixture(case); led=r/'jobs/submitted_by_submit_all.tsv'; calls=r/'calls'; cancels=r/'cancels'
  write(led,'old\t999999\n' if case=='stale' else '')
  if case=='stale':led.chmod(0o444)
  exe(r/'bin/sbatch','echo called >> "$CALLS"\n[ "${BREAK_APPEND:-}" != yes ] || chmod 444 "$LEDGER"\necho "$((122 + $(wc -l < "$CALLS")))"\n')
  p=run(['bash',r/'setup_and_run_all.sh','run'],renv(r,HW_PREPARE_CMD='true',LEDGER=led,CALLS=calls,CANCELS=cancels,BREAK_APPEND='yes' if case=='append' else 'no'),r)
  print(case,p.returncode,p.stdout[-1400:])
  if case=='good':check(p.returncode==0 and calls.exists() and led.read_text().count('\n')>50,'valid ledger records actual mocked submissions')
  elif case=='stale':check(p.returncode!=0 and not calls.exists() and not cancels.exists() and led.read_text()=='old\t999999\n','unwritable stale ledger prevents submission and cancellation')
  else:check(calls.exists() and len(calls.read_text().splitlines())==1 and p.returncode!=0 and cancels.exists() and '123' in cancels.read_text(),'accepted unrecordable job is cancelled')

def fx25():
 r=fixture('prepare'); src=r/'input/hw2/github_Hortaea_werneckii/assemblies/Hw2/Hw2.fasta.gz';src.parent.mkdir(parents=True)
 with gzip.open(src,'wb') as f:f.write(b'>a\nACGT\n')
 d=r/'work/asm/hw2';d.mkdir(parents=True);target=write(W/'precious','precious\n');(d/'final.fasta.tmp').symlink_to(target)
 p=run(['bash',r/'scripts/01_prepare_hw2.sh'],renv(r),r); print(p.stdout)
 check(p.returncode==0 and (d/'final.fasta').read_text()=='>a\nACGT\n','real gzip preparation ran and produced expected assembly')
 check(target.read_text()=='precious\n' and not (d/'final.fasta').is_symlink(),'fixed temporary name cannot overwrite symlink target')
 # Two actual invocations must get different output inodes, even while both decompressors are active.
 mock=r/'mock_zcat.py'
 write(mock, "import os,sys,time,gzip\nfrom pathlib import Path\nd=Path(os.environ['CALL_DIR']); (d/str(os.getpid())).write_text(str(os.fstat(1).st_ino))\nend=time.monotonic()+10\nwhile len(list(d.iterdir()))<2:\n if time.monotonic()>end: raise RuntimeError('second decompressor never ran')\n time.sleep(.01)\nsys.stdout.buffer.write(gzip.open(sys.argv[1],'rb').read())\n")
 exe(r/'bin/zcat','exec python3 -S "'+str(mock)+'" "$@"\n')
 calls=W/'decompressors';calls.mkdir();e=renv(r,CALL_DIR=calls)
 ps=[subprocess.Popen(['bash',str(r/'scripts/01_prepare_hw2.sh')],env=e,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True) for _ in range(2)]
 results=[p.communicate(timeout=15)[0] for p in ps];inodes=[f.read_text() for f in calls.iterdir()]
 check(len(inodes)==2 and len(set(inodes))==2 and all(p.returncode==0 for p in ps),'concurrent preparations actually ran with distinct temporary output inodes')
 (r/'bin/zcat').unlink()
 write(src,'bad gzip');p=run(['bash',r/'scripts/01_prepare_hw2.sh'],renv(r),r)
 check(p.returncode!=0 and (d/'final.fasta').read_text()=='>a\nACGT\n','damaged gzip fails while previous final assembly remains')

def fx26():
 if os.geteuid()==0:raise RuntimeError('permission injection requires an unprivileged user')
 r=fixture('marker');s=(r/'jobs/06_tests.sbatch').read_text();fn=s[s.index('step() {'):s.index('\ns_contiguity()')]
 for bad in (False,True):
  d=W/('bad' if bad else 'good');(d/'steps').mkdir(parents=True);write(d/'steps/producer.done','old');(d/'steps').chmod(0o555 if bad else 0o755)
  script=write(W/'step.sh',fn+'\nproducer() { echo ran >> "$BIG/producer-ran"; '+('false' if bad else 'true')+'; }\nconsumer() { echo ran >> "$BIG/consumer-ran"; }\nstep producer producer\nstep consumer consumer producer\nprintf "%s" "$FAILED" > "$BIG/failed"\n')
  p=run(['bash',script],renv(r,BIG=d,FAILED='',FORCE='1')); print(p.stdout);(d/'steps').chmod(0o755)
  check((d/'producer-ran').exists(),'producer actually ran')
  if bad:check((d/'steps/producer.done').exists(),'failure injection left the old producer marker in place')
  check((not (d/'consumer-ran').exists() and 'consumer' in (d/'failed').read_text()) if bad else ((d/'consumer-ran').exists() and not (d/'failed').read_text()),'failed producer blocks consumer despite unremovable marker' if bad else 'successful producer permits consumer')

def fx27():
 r=fixture('grep');s=(r/'scripts/06_fetch_databases.sh').read_text();fn=s[s.index('add_entry() {'):s.index('\n}\n',s.index('add_entry() {'))+3]
 tab=r/'table';original='name\tsource\tversion\tdate\tmd5\tuse\nx\told\tv\td\tm\tu\ny\tkeep\tv\td\tm\tu\n';db=r/'db';db.mkdir(exist_ok=True)
 script=write(W/'grep.sh','set -euo pipefail\n'+fn+'\nadd_entry x new v d m u\n')
 write(tab,original);p=run(['bash',script],renv(r,TAB=tab,DBS=db));check(p.returncode==0 and 'x\tnew' in tab.read_text() and 'y\tkeep' in tab.read_text(),'normal provenance replacement runs and retains other rows')
 real=shutil.which('grep');exe(r/'bin/grep',f'echo "$*" >> "$GREP_CALLS"\nif [ "$1" = -v ]; then exit 2; fi\nexec {real} "$@"\n');write(tab,original)
 p=run(['bash',script],renv(r,TAB=tab,DBS=db,GREP_CALLS=r/'grep-calls'));print(p.stdout)
 check((r/'grep-calls').exists() and '-v' in (r/'grep-calls').read_text(),'failing grep path actually executed')
 check(p.returncode!=0 and tab.read_text()==original,'grep exit 2 propagates without replacing provenance')

def fx28():
 r=fixture('hardlinks');source=write(W/'source','real sequence\n');d,m=fetch(r,'dest',source);data=d/'R/data';shutil.copyfile(source,data)
 shared_marker=write(W/'shared-marker','old marker\n');os.link(shared_marker,str(data)+'.md5ok')
 shared_report=write(W/'shared-report','previous report\n');os.link(shared_report,d/'fetch_report.tsv')
 p=dofetch(r,d,m);print(p.stdout)
 check(p.returncode==0 and data.read_bytes()==source.read_bytes(),'real local manifest verified without network')
 check(shared_marker.read_text()=='old marker\n' and shared_report.read_text()=='previous report\n','marker/report hardlink aliases remain unchanged')
 check((d/'fetch_report.tsv').read_text().startswith('previous report\n') and (d/'fetch_report.tsv').stat().st_ino!=shared_report.stat().st_ino,'report appends history using a new inode')
 check(Path(str(data)+'.md5ok').stat().st_ino!=shared_marker.stat().st_ino,'marker uses a new inode')
 p=dofetch(r,d,m);check(p.returncode==0 and 'already verified' in p.stdout,'subsequent run reuses verified input')

def fx29():
 for missing in (False,True):
  r=fixture('missing' if missing else 'complete');write(r/'input/CHECKSUMS.md5','abc  regular\n');write(r/'input/regular','data');write(r/'input/manifests/pacbio_deposited_fastq.tsv','run\tname\tsize\tmd5\turl\nR\tdep\t1\tx\tunused\n');[write(r/'input/manifests'/(m+'.tsv'),'run\tname\tsize\tmd5\turl\n') for m in ('pacbio_files','rna_sra_files','illumina2013_sra_files')]
  dep=r/'input/pacbio_deposited/R/dep'
  if not missing:write(dep,'data')
  exe(r/'bin/sbatch','echo "$*" >> "$CALLS"\n[ "$(basename "${@: -1}")" = 01_fetch_inputs.sbatch ] || exit 97\nmkdir -p "$HW/input/pacbio_deposited/R"\necho data > "$HW/input/pacbio_deposited/R/dep"\necho 101\n');exe(r/'bin/sacct','echo COMPLETED\n')
  p=run(['bash',r/'setup_and_run_all.sh','inputs'],renv(r,CALLS=r/'calls'),r);print(p.stdout)
  check(p.returncode==0 and dep.exists(),'real stage inputs leaves deposited file present')
  check((r/'calls').exists() if missing else not (r/'calls').exists(),'missing deposited file triggers mocked download' if missing else 'complete input stage skips download')

globals()[sys.argv[1]]();finish()
