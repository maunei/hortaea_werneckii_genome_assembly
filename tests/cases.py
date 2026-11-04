from support import *
import re

def fx01():
    r=repo();log=W/'calls';exe(r/'bin/scontrol','exit 0\n')
    q=r/'environments/04_I_qc/bin';q.mkdir(parents=True)
    exe(q/'minimap2','echo "mapper $*" >> "$CALLS"\nif [[ "$*" == *map-pb* ]] && [ "$FAULT" = mapper ]; then echo injected mapper >&2; exit 42; fi\nprintf "data\\n"\n')
    exe(r/'bin/gzip','echo "gzip $*" >> "$CALLS"\nif [ "$#" = 0 ] && [ "$FAULT" = gzip ]; then echo injected gzip >&2; exit 42; fi\nexec /usr/bin/gzip "$@"\n')
    exe(r/'bin/mv','echo "rename $*" >> "$CALLS"\nif [ "$FAULT" = rename ]; then echo injected rename >&2; exit 42; fi\nexec /usr/bin/mv "$@"\n')
    pyexe(r/'environments/04_probe/bin/python','import os,sys\nos.execvp("python3",["python3","-S"]+sys.argv[1:])\n')
    write(r/'scripts/07_find_disagreements.py','import sys,json\nfrom pathlib import Path\nPath(sys.argv[4]).write_text("id\\n")\nPath(sys.argv[sys.argv.index("--stats")+1]).write_text("{}")\n')
    write(r/'scripts/07_compact_read_alignments.py','import os,sys\nwith open(os.environ["CALLS"],"a") as f:f.write("compactor\\n")\nsys.stdin.read()\nprint("header\\nrow")\nif os.environ["FAULT"]=="compactor":print("injected compactor failure",file=sys.stderr);raise SystemExit(42)\n')
    write(r/'scripts/07_adjudicate.py','import os\nwith open(os.environ["CALLS"],"a") as f:f.write("adjudicator\\n")\n')
    for fault in ('none','mapper','compactor','gzip','rename'):
        shutil.rmtree(r/'logs');(r/'logs').mkdir()
        work=W/('work_'+fault)
        for a in ('a','b'):write(work/'asm'/a/'final.fasta','>a\nACGT\n')
        write(work/'reads/pacbio/hq_clean.fastq','@r\nACGT\n+\nIIII\n');log.write_text('')
        p=run(['bash',r/'jobs/07_compare_adjudicate.sbatch'],renv(r,HW_WORK=work,A_ASM='a',B_ASM='b',FAULT=fault,CALLS=log),r)
        calls=log.read_text();c=work/'aln/07_reads/hq_clean_to_a.tsv.gz'
        if fault=='none':
            check(p.returncode==0 and c.exists() and 'row' in gzip.decompress(c.read_bytes()).decode() and 'adjudicator' in calls,'FX-01 successful producer publishes usable cache and reaches consumer')
        else:
            marker={'mapper':'mapper -x map-pb','compactor':'compactor','gzip':'gzip ','rename':'rename '}[fault]
            check(marker in calls,'FX-01 '+fault+' path actually ran')
            check(p.returncode!=0 and not c.exists(),'FX-01 '+fault+' failure rejects publication (rc='+str(p.returncode)+')')
            diagnostics=p.stdout+'\n'+''.join(f.read_text(errors='replace') for f in (r/'logs').rglob('*.log'))
            check(bool(re.search(r'error|fail|injected|cannot',diagnostics,re.I)),'FX-01 failure has a diagnostic')

def fx02():
    r=repo();source=write(W/'source','good');shared=write(W/'shared','precious')
    d,m=fetch(r,'positive',source);p=dofetch(r,d,m);check(p.returncode==0 and (d/'R/data').read_bytes()==b'good','FX-02 ordinary verified download still works')
    d,m=fetch(r,'partlink',source);(d/'R/data.part').symlink_to(shared);p=dofetch(r,d,m)
    check(shared.read_bytes()==b'precious','FX-02 .part symlink target stays unchanged')
    check(p.returncode==0 and (d/'R/data').is_file() and not (d/'R/data').is_symlink(),'FX-02 successful publication is an owned regular file')
    shared.write_text('precious');d,m=fetch(r,'part_hardlink',source);os.link(shared,d/'R/data.part');p=dofetch(r,d,m)
    check(shared.read_bytes()==b'precious','FX-02 existing regular .part hardlink cannot alter another file')
    check(p.returncode==0 and (d/'R/data').exists() and (d/'R/data').stat().st_ino!=shared.stat().st_ino,'FX-02 final owns a new inode rather than publishing existing temporary inode')
    shared.write_text('precious');d,m=fetch(r,'reportlink',source);(d/'fetch_report.tsv').symlink_to(shared);p=dofetch(r,d,m)
    check(shared.read_bytes()==b'precious','FX-02 fetch report does not append through shared link')
    check(p.returncode==0 and (d/'fetch_report.tsv').is_file() and not (d/'fetch_report.tsv').is_symlink(),'FX-02 report is published locally after real download')
    shared.write_text('precious');d,m=fetch(r,'markerlink',source);(d/'R/data.md5ok').symlink_to(shared);p=dofetch(r,d,m)
    check(shared.read_bytes()==b'precious','FX-02 verification marker write does not follow shared link')
    check(p.returncode!=0 or ((d/'R/data.md5ok').is_file() and not (d/'R/data.md5ok').is_symlink()),'FX-02 successful marker publication is local')
    src=W/'input_source';write(src/'nested/real.dat','data');write(src/'nested/orphan.part','partial');write(src/'nested/fetch_report.tsv','old report')
    write(r/'input/CHECKSUMS.md5',hashlib.md5(b'data').hexdigest()+'  nested/real.dat\n');[write(r/'input/manifests'/(m+'.tsv'),'run\tname\tsize\tmd5\turl\n') for m in ('pacbio_files','rna_sra_files','illumina2013_sra_files','pacbio_deposited_fastq')];settings(r,f'input_source: {src}\n')
    p=run(['bash',r/'setup_and_run_all.sh','inputs'],renv(r),r)
    check(p.returncode==0 and (r/'input/nested/real.dat').is_file(),'FX-02 input-source linking really links required data')
    check(not (r/'input/nested/orphan.part').is_symlink() and not (r/'input/nested/fetch_report.tsv').is_symlink(),'FX-02 transient .part/report source files are not linked')

# FX-03 is split into independently diagnosable scripts below.
def fx03_filters():
    r=W/'runner';(r/'tests').mkdir(parents=True);shutil.copyfile(HW/'tests/run_tests.sh',r/'tests/run_tests.sh')
    exe(r/'tests/t03_settings.sh','echo selected >> "$SELECTION"\n')
    exe(r/'tests/t04_other.sh','echo WRONG >> "$SELECTION"; exit 51\n')
    for filt in ('03','t03','t03_settings.sh'):
        marker=W/('selection_'+filt);p=run(['bash',r/'tests/run_tests.sh',filt],env(SELECTION=marker),r)
        check(p.returncode==0 and marker.exists() and marker.read_text().splitlines()==['selected'],'FX-03 filter '+filt+' executes exactly the requested test (rc='+str(p.returncode)+')')

def fx03_t09():
    r=repo();archive=W/'archive';out=archive/'09_summary';out.mkdir(parents=True)
    for f in ('measures.tsv','verdict.tsv','noise_scale.tsv','verdict.json'):write(out/f,'expected\n')
    log=W/'summary.calls'
    body='import os\nfrom pathlib import Path\nwith open(os.environ["PROBE"],"a") as f:f.write("ran\\n")\n'
    write(r/'scripts/09_summary.py',body+'p=Path(os.environ["RESULTS"])/"09_summary"\np.mkdir(parents=True,exist_ok=True)\nfor f in ("measures.tsv","verdict.tsv","noise_scale.tsv","verdict.json"):(p/f).write_text("expected\\n")\n')
    e=renv(r,PY='python3',HW_TEST_RESULTS=archive,PROBE=log)
    p=run(['bash',r/'tests/t09_archived_results.sh'],e,r);check(p.returncode==0 and log.exists() and log.read_text().splitlines()==['ran'],'FX-03 t09 accepts genuine matching regeneration')
    write(r/'scripts/09_summary.py',body);p=run(['bash',r/'tests/t09_archived_results.sh'],e,r)
    check(log.exists() and len(log.read_text().splitlines())==2,'FX-03 no-op mutant really executed')
    check(p.returncode!=0,'FX-03 t09 rejects no-op leaving copied old outputs (rc='+str(p.returncode)+')')

def fx03_t02():
    r=repo();good=(r/'scripts/submit_all.sh').read_text()
    p=run(['bash',r/'tests/t02_submission.sh'],renv(r),r);check(p.returncode==0,'FX-03 t02 positive original fixture completes')
    # Mutate only nonempty argument fields *after* the real submitter ran. Preserve
    # field count, IDs, dependencies and all mock submission/failure behavior.
    shutil.copyfile(r/'scripts/submit_all.sh',r/'scripts/submit_original.sh')
    exe(r/'scripts/submit_all.sh','bash "$HW/scripts/submit_original.sh" "$@"; rc=$?\nif [ -z "${DRYRUN:-}" ] && [ -f "$LEDGER" ]; then\n python3 - "$LEDGER" <<\'P\'\nimport sys\nfrom pathlib import Path\np=Path(sys.argv[1]);rows=[]\nfor line in p.read_text().splitlines():\n r=line.split("\\t");r=r[:4]+[""];rows.append("\\t".join(r))\np.write_text("\\n".join(rows)+"\\n")\nP\n echo mutated >> "$MUTATION_PROBE"\nfi\nexit "$rc"\n')
    marker=W/'mutations';p=run(['bash',r/'tests/t02_submission.sh'],renv(r,MUTATION_PROBE=marker),r)
    check(marker.exists() and marker.stat().st_size>0,'FX-03 empty-argument mutation really ran')
    check(p.returncode!=0,'FX-03 t02 rejects empty argument values despite five fields (rc='+str(p.returncode)+')')

def fx03_t04():
    r=repo();p=run(['bash',r/'tests/t04_fetch_archive.sh'],renv(r),r)
    check(p.returncode==0,'FX-03 t04 accepts ordinary real downloader behavior')
    shutil.copyfile(r/'scripts/fetch_archive.py',r/'scripts/fetch_original.py')
    wrapper='''import os,sys,csv,runpy
from pathlib import Path
m,d=sys.argv[1:3];row=next(csv.DictReader(open(m),delimiter='\\t'));fn=Path(d)/row['run']/row['name'];fault=os.environ['MUTATION']
with open(os.environ['ENTRY'],'a') as f:f.write('entered\\n')
if fault=='size' and fn.is_file() and not fn.is_symlink() and fn.stat().st_size!=int(row['size']):
    with open(os.environ['TRIGGER'],'a') as f:f.write('triggered\\n')
    raise SystemExit(0)
part=Path(str(fn)+'.part')
if fault=='partlink' and part.is_symlink():
    with open(os.environ['TRIGGER'],'a') as f:f.write('triggered\\n')
    part.write_bytes(b'BROKEN SHARED SOURCE')
rc=0
try:runpy.run_path(str(Path(__file__).with_name('fetch_original.py')),run_name='__main__')
except SystemExit as e:rc=e.code or 0
if fault=='leftpart' and rc:
    part.write_bytes(b'incomplete')
    with open(os.environ['TRIGGER'],'a') as f:f.write('triggered\\n')
raise SystemExit(rc)
'''
    write(r/'scripts/fetch_archive.py',wrapper)
    for fault in ('size','leftpart','partlink'):
        entry=W/(fault+'.entry');trigger=W/(fault+'.trigger')
        p=run(['bash',r/'tests/t04_fetch_archive.sh'],renv(r,MUTATION=fault,ENTRY=entry,TRIGGER=trigger),r)
        check(entry.exists(),'FX-03 t04 really runs mutated downloader for '+fault)
        check(trigger.exists(),'FX-03 t04 exercises '+fault+' scenario')
        check(p.returncode!=0,'FX-03 t04 detects '+fault+' mutant (rc='+str(p.returncode)+')')

def submission_fixture(r,mode,ledger):
    settings(r);exe(r/'bin/squeue','exit 0\n');exe(r/'bin/scontrol','exit 0\n')
    pyexe(r/'bin/scancel','import os,sys\nwith open(os.environ["CANCELS"],"a") as f:f.write(" ".join(sys.argv[1:])+"\\n")\n')
    pyexe(r/'bin/sbatch','import os,sys,json\nwith open(os.environ["SUBMITS"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint(900)\n')
    exe(r/'scripts/submit_all.sh','echo ran >> "$CHILD_PROBE"\np="${LEDGER:-jobs/submitted_by_submit_all.tsv}"; printf "%s\\n" "$p" > "$LEDGER_PROBE"; mkdir -p "$(dirname "$p")"; : > "$p"\nif [ "$CHILD_MODE" = firstfail ]; then exit 42; fi\nprintf "first\\t11\\t\\tfirst.sbatch\\t--export=ALL,ASM=a\\n" >> "$p"\nif [ "$CHILD_MODE" = partialfail ]; then exit 42; fi\nprintf "summary\\t12\\tafterany:11\\t09_summary.sbatch\\t\\n" >> "$p"\n')
    return renv(r,LEDGER=ledger,CHILD_MODE=mode,CANCELS=W/'cancels',SUBMITS=W/'submits',CHILD_PROBE=W/'child',LEDGER_PROBE=W/'selected_ledger')

def fx08():
    r=repo();default=r/'jobs/submitted_by_submit_all.tsv';alternate=W/'alternate.tsv'
    e=submission_fixture(r,'success',default);p=run(['bash',r/'setup_and_run_all.sh','run'],e,r)
    check(p.returncode==0 and 'last job' in p.stdout and '12' in p.stdout,'FX-08 standard-ledger success finds its actual summary')
    for mode in ('firstfail','partialfail','success'):
        write(default,'stale\t999999\t\told.sbatch\t\n');(W/'cancels').unlink(missing_ok=True);(W/'submits').unlink(missing_ok=True);(W/'child').unlink(missing_ok=True);(W/'selected_ledger').unlink(missing_ok=True)
        e=submission_fixture(r,mode,alternate)
        if mode=='success':
            with (r/'config/local.sh').open('a') as f:f.write('export HW_MAIL_WHEN=ALL\nexport HW_MAIL=test@invalid.test\n')
        p=run(['bash',r/'setup_and_run_all.sh','run'],e,r);calls=[x for x in (W/'cancels').read_text().split() if re.fullmatch(r'[0-9]+(?:_[0-9]+)?',x)] if (W/'cancels').exists() else []
        selected=Path((W/'selected_ledger').read_text().strip()) if (W/'selected_ledger').exists() else W/'missing_ledger'
        if not selected.is_absolute():selected=r/selected
        check((W/'child').exists() and selected.exists(),'FX-08 child really initialized its selected attempt ledger in '+mode)
        if mode=='success':
            check(p.returncode==0,'FX-08 alternate-ledger successful summary lookup')
            submits=[json.loads(x) for x in (W/'submits').read_text().splitlines()] if (W/'submits').exists() else []
            check(bool(submits),'FX-08 notification actually submitted to mock')
            args=' '.join(sum(submits,[]));check('--dependency=afterany:12' in args and '999999' not in args,'FX-08 notification uses current summary, never stale ID')
            wrap=next((x[7:] for row in submits for x in row if x.startswith('--wrap=')),'')
            if wrap:
                exe(r/'bin/sleep','exit 0\n')
                accounting_mock(r)
                probe=W/'notification_query'
                notified=run(['bash','-c',wrap],dict(e,ACCOUNT_CASE='full',ACCOUNT_PROBE=str(probe)),r)
                queries=probe.read_text() if probe.exists() else ''
                check(notified.returncode==0 and '11' in queries and '12' in queries and '999999' not in queries,'FX-08 notification queries the actual attempt IDs')
            else:check(False,'FX-08 notification has a runnable captured entry point')
        else:
            check(p.returncode!=0,'FX-08 refused submission fails setup in '+mode)
            check('999999' not in calls,'FX-08 stale default ledger never canceled in '+mode)
            check(calls==(['11'] if mode=='partialfail' else []),'FX-08 only IDs accepted during this attempt are canceled in '+mode+' (observed '+str(calls)+')')

def summary_fixture(r):
    data=r/'results'
    for a in ('hw2','proc_r1','proc_r2','proc_r3'):
        write(data/'06_tests'/a/'summary.json',json.dumps({'contiguity':{'all':{'n50':10 if a=='hw2' else 20,'ng50':10 if a=='hw2' else 20,'aun':10 if a=='hw2' else 20,'l50':5 if a=='hw2' else 2}},'busco':{'complete_percent':100},'depth':{'frac_0_5_to_1_5':.8 if a=='hw2' else .9},'redundancy':{'false_duplication_fraction':.02 if a=='hw2' else .01}}))
        write(data/'06_transcripts'/a/'summary.json',json.dumps({'frac_pass_ge90pct_ge95id':.8 if a=='hw2' else .9}))
    for a in ('proc_r1','proc_r2','proc_r3'):
        write(data/'07_compare'/f'{a}_vs_hw2/summary.json',json.dumps({'fraction_of_decided_for_A':{'proportion':.9,'ci95_low':.8,'ci95_high':.99,'of':10},'decided_for_A':{'count':9},'decided_for_B':{'count':1},'disagreements':10}))
        write(data/'08_illumina_accuracy/shared'/f'{a}_vs_hw2/summary.json',json.dumps({'assemblies':{x:{'specific_per_mb_callable':{'all':20 if x=='hw2' else 5,'snv':1,'ins':2,'del':2}} for x in ('hw2',a)}}))
    return data

def fx09():
    r=repo();data=summary_fixture(r);e=renv(r,RESULTS=data)
    p=run(['python3','-S',r/'scripts/09_summary.py'],e,r);v=json.loads((data/'09_summary/verdict.json').read_text()) if p.returncode==0 else {}
    check(p.returncode==0 and v.get('verdict',{}).get('3',{}).get('verdict')=='better','FX-09 valid decided comparison remains assessable')
    for a in ('proc_r1','proc_r2','proc_r3'):
        q=data/'07_compare'/f'{a}_vs_hw2/summary.json';old=q.read_text();d=json.loads(old);d['fraction_of_decided_for_A'].update(proportion=None,ci95_low=None,ci95_high=None,of=0);d['decided_for_A']['count']=d['decided_for_B']['count']=0;q.write_text(json.dumps(d));out=data/'09_summary/verdict.json';out.unlink(missing_ok=True);(data/'09_summary/measures.tsv').unlink(missing_ok=True)
        p=run(['python3','-S',r/'scripts/09_summary.py'],e,r);v=json.loads(out.read_text()) if out.exists() else {};state=v.get('verdict',{}).get('3',{}).get('verdict','').lower()
        check((data/'09_summary/measures.tsv').is_file(),'FX-09 summary reads fixture for '+a)
        check(p.returncode==0 and ('incomplete' in state or 'not assessable' in state),'FX-09 zero/null '+a+' gives a verdict instead of crashing (rc='+str(p.returncode)+')')
        if p.returncode:print('observed: '+p.stdout.splitlines()[-1])
        if v:check('new assembly is better' not in v.get('overall','').lower(),'FX-09 no overall better claim from unassessable line 3')
        q.write_text(old)

def fx10():
    r=repo();defs=setup_defs(r);exe(r/'bin/squeue','exit 0\n');exe(r/'bin/sleep','exit 0\n')
    exe(r/'bin/sacct','echo queried >> "$QUERY_PROBE"\ncase "$ACCOUNT_CASE" in\n full) printf "11|first|COMPLETED|0:0\\n12|second|COMPLETED|0:0\\n";;\n partial) printf "11|first|COMPLETED|0:0\\n";;\n empty) :;;\n fail) echo unavailable >&2; exit 42;;\n fail_with_rows) printf "11|first|COMPLETED|0:0\\n12|second|COMPLETED|0:0\\n"; exit 42;;\n failed_job) printf "11|first|COMPLETED|0:0\\n12|second|FAILED|1:0\\n";;\nesac\n')
    for mode in ('full','partial','empty','fail','fail_with_rows','failed_job'):
        probe=W/('query_'+mode);p=run(['bash','-c','source "$1"; wait_jobs 11,12 fixture','_',defs],renv(r,ACCOUNT_CASE=mode,QUERY_PROBE=probe),r)
        check(probe.exists(),'FX-10 real wait_jobs queried '+mode+' accounting')
        check(p.returncode==0 if mode=='full' else p.returncode!=0,'FX-10 '+mode+' accounting '+('accepted' if mode=='full' else 'rejected')+' (rc='+str(p.returncode)+')')


def fx11():
    r=repo();base=f'mail_when: NONE # comment\nmodules: # empty\nenvs_dir: {r}/environments\ndbs_dir: {r}/db\n'
    # a # inside a quoted value is data (tested with the account; a path may not hold a # or a space); after the closing quote only a comment may follow
    for mode,acct,value,expected_acct,expected in [('unquoted','test # comment',str(W/'normal')+' # comment','test',str(W/'normal')),('double','"te#st" # comment','"'+str(W/'a_b')+'" # comment','te#st',str(W/'a_b')),('single',"'te # st' # comment","'"+str(W/'c_d')+"' # comment",'te # st',str(W/'c_d'))]:
        write(r/'settings.yaml',base+'account: '+acct+'\nwork_dir: '+value+'\n');p=run(['bash',r/'setup_and_run_all.sh','settings'],renv(r),r)
        q=run(['bash','-c','source "$1"; printf "%s\\n%s\\n%s\\n" "$HW_WORK" "$HW_MODULES" "$HW_ACCOUNT"','_',r/'config/local.sh'],renv(r)) if p.returncode==0 else None
        lines=q.stdout.splitlines() if q else []
        check(p.returncode==0 and lines==[expected,'',expected_acct],'FX-11 '+mode+' comments preserve quoted data/empty modules (got '+repr(lines)+')')
    for bad in ['"'+str(W/'a b')+'"','"'+str(W/'q')+'\\" # name"',"'"+str(W/'s')+"'' # name'",'"'+str(W/'a')+'"b',str(W/'a;b')]:
        write(r/'settings.yaml',base+'account: test\nwork_dir: '+bad+'\n');p=run(['bash',r/'setup_and_run_all.sh','settings'],renv(r),r)
        check(p.returncode!=0 and 'settings.yaml: work_dir' in (p.stdout or '')+(p.stderr or ''),'FX-11 unsupported value refused, not shortened: '+bad[-12:])


def fx12():
    r=repo();source=write(W/'source','good');digest=hashlib.md5(b'good').hexdigest()
    d,m=fetch(r,'positive',source);write(d/'R/data','good');write(d/'R/data.md5ok',digest+'\n');p=dofetch(r,d,m)
    check(p.returncode==0 and (d/'R/data').read_bytes()==b'good','FX-12 matching marker/size remains usable')
    d,m=fetch(r,'wrong_marker',source);write(d/'R/data','evil');write(d/'R/data.md5ok','0'*32+'\n');p=dofetch(r,d,m)
    check(p.returncode==0 and (d/'R/data').read_bytes()==b'good','FX-12 wrong marker forces actual content verification/repair')
    check((d/'R/data.md5ok').is_file() and (d/'R/data.md5ok').read_text().strip()==digest,'FX-12 repaired marker has expected digest')
    d,m=fetch(r,'size_mismatch',source);write(d/'R/data','bad-size');write(d/'R/data.md5ok',digest+'\n');p=dofetch(r,d,m)
    check(p.returncode==0 and (d/'R/data').read_bytes()==b'good','FX-12 matching marker cannot bless incorrect size')
    d,m=fetch(r,'failed_replacement',source,'0'*32);write(d/'R/data','evil');p=dofetch(r,d,m)
    check(p.returncode!=0 and 'MISMATCH' in p.stdout.upper(),'FX-12 injected checksum rejection really occurred')
    check(not (d/'R/data').exists(),'FX-12 failed repair leaves no bad final destination')

def fx13():
    r=repo();exe(r/'bin/scontrol','exit 0\n');q=r/'environments/04_I_qc/bin';rna=r/'environments/04_A_rna/bin';screen=r/'environments/04_screen/bin'
    pyexe(rna/'fasterq-dump','''import os,sys
from pathlib import Path
with open(os.environ['CALLS'],'a') as f:f.write('fasterq\\n')
o=Path(sys.argv[sys.argv.index('-O')+1]);o.mkdir(parents=True,exist_ok=True)
for mate in (1,2):
 name='different' if os.environ['FAULT']=='names' and mate==2 else 'same'
 (o/('RUN_'+str(mate)+'.fastq')).write_text('@'+name+'/'+str(mate)+'\\nACGT\\n+\\nIIII\\n')
''')
    pyexe(q/'seqkit','''import sys,gzip
from pathlib import Path
p=Path(sys.argv[-1]);n=len(gzip.decompress(p.read_bytes()).splitlines())//4
print('file\\tformat\\ttype\\tnum_seqs');print(str(p)+'\\tFASTQ\\tDNA\\t'+str(n))
''')
    pig='''import os,sys,gzip
from pathlib import Path
a=sys.argv[1:];p=Path(a[-1]);decomp=any('d' in x and x.startswith('-') for x in a)
with open(os.environ['CALLS'],'a') as f:f.write(('decompress ' if decomp else 'compress ')+str(p)+'\\n')
if decomp:
 mate='1' if '_1.' in p.name else '2'
 if os.environ['FAULT'] in ('both','mate'+mate):
  with open(os.environ['CALLS'],'a') as f:f.write('injected decompressor '+mate+'\\n')
  sys.stdout.buffer.write(gzip.decompress(p.read_bytes()))
  print('injected decompressor failure after complete output',file=sys.stderr);raise SystemExit(42)
 sys.stdout.buffer.write(gzip.decompress(p.read_bytes()))
else:sys.stdout.buffer.write(gzip.compress(p.read_bytes()))
'''
    pyexe(screen/'pigz',pig);pyexe(r/'bin/pigz',pig);pyexe(r/'bin/gzip',pig)
    for mode in ('same','names','mate1','mate2','both'):
        work=W/('convert_'+mode);log=W/('convert_'+mode+'.calls');write(r/'input/illumina2013/RUN/RUN','archive')
        p=run(['bash',r/'jobs/03_convert.sbatch'],renv(r,HW_WORK=work,RUN='RUN',GROUP='illumina2013',EXPECTED=1,NEEDED='RUN',FAULT=mode,CALLS=log),r)
        calls=log.read_text() if log.exists() else '';out=work/'reads/illumina2013'
        check('fasterq' in calls and 'compress ' in calls,'FX-13 conversion/compression actually ran for '+mode)
        if mode=='same':check(p.returncode==0 and (out/'RUN_1.fastq.gz').is_file() and (out/'READY_03').exists(),'FX-13 identical names publish checked pair')
        else:
            if mode!='names':check('injected decompressor' in calls,'FX-13 '+mode+' fault actually injected')
            check(p.returncode!=0 and not (out/'READY_03').exists(),'FX-13 '+mode+' rejects conversion (rc='+str(p.returncode)+')')
            check(not (out/'RUN_1.fastq.gz').exists() and not (out/'RUN_2.fastq.gz').exists(),'FX-13 '+mode+' publishes neither mate')

def fx14():
    r=repo();data=r/'results';digest='a'*32
    expected='item\tgroup\texpected\tlow\thigh\trule\n'+''.join(f'assembly_sequences_md5:proc_r{i}\tchecksum\t{digest}\t{digest}\t{digest}\texact\n' for i in (1,2,3));write(r/'validation/expected.tsv',expected)
    write(data/'09_summary/measures.tsv','measure\tline\tproc_r1\tproc_r2\tproc_r3\n');write(data/'02_pacbio_reads/merged_seqkit_stats.tsv','file\tnum_seqs\nhq_subreads.fastq\t1\nfiltered_subreads.fastq\t1\n')
    for mode in ('full','partial','missing_token'):
        rows=[f'proc_r{i}\t{digest}' for i in (1,2,3)]
        if mode=='partial':rows=rows[:1]
        if mode=='missing_token':rows=[rows[0],'proc_r2\tmissing','proc_r3\tmissing']
        write(data/'09_summary/replicate_check.tsv','run\tpolished_assembly_sequences_md5\n'+'\n'.join(rows)+'\n');report=data/'10_validation/validation_report.txt';report.unlink(missing_ok=True)
        p=run(['python3','-S',r/'scripts/10_validate.py','check',data],renv(r),r)
        check(p.returncode==0 and report.is_file(),'FX-14 validator really writes '+mode+' report')
        text=report.read_text() if report.exists() else '';lines=text.splitlines();headers='\n'.join(lines[:next((i for i,l in enumerate(lines) if not l.strip()),len(lines))])
        if mode=='full':check('identical' in headers and 'differs' not in headers,'FX-14 complete equal checksums remain identical')
        else:
            check('in every run' not in headers.lower(),'FX-14 '+mode+' does not overstate checksum coverage')
            for a in ('proc_r2','proc_r3'):
                check(any(a in line and ('missing' in line.lower() or 'not available' in line.lower()) for line in lines),'FX-14 '+mode+' identifies unavailable '+a)
            if mode=='missing_token':check(not any(l.startswith('[differs] assembly_sequences_md5:') for l in lines),'FX-14 missing sentinel is unavailable, not sequence drift')


def accounting_mock(r):
    pyexe(r/'bin/sacct','''import os,sys,json
from pathlib import Path
with open(os.environ['ACCOUNT_PROBE'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
mode=os.environ['ACCOUNT_CASE'];a=sys.argv[1:];fields=['State']
for i,x in enumerate(a):
 if x in ('-o','--format') and i+1<len(a):fields=a[i+1].split(',')
 elif x.startswith('--format='):fields=x.split('=',1)[1].split(',')
rows=[('11','first','COMPLETED'),('12','summary','COMPLETED')]
if mode=='partial':rows=rows[:1]
if mode=='empty':rows=[]
if mode=='failed_job':rows[-1]=('12','summary','FAILED')
for jid,name,state in rows:
 d={'jobid':jid,'jobidraw':jid,'jobname':name,'state':state,'exitcode':'0:0' if state=='COMPLETED' else '1:0'}
 print('|'.join(d.get(k.lower(),'') for k in fields))
if mode=='fail_with_rows':raise SystemExit(42)
''')

def fx22():
    # Added requirement: the final notification must not report successful whole-run
    # completion from partial sacct output or from a failed accounting command.
    r=repo();default=r/'jobs/submitted_by_submit_all.tsv';e=submission_fixture(r,'success',default)
    with (r/'config/local.sh').open('a') as f:f.write('export HW_MAIL_WHEN=ALL\nexport HW_MAIL=test@invalid.test\n')
    p=run(['bash',r/'setup_and_run_all.sh','run'],e,r)
    check(p.returncode==0 and (W/'submits').exists(),'FX-22 actual setup submits notification to mock')
    args=[json.loads(s) for s in (W/'submits').read_text().splitlines()] if (W/'submits').exists() else []
    wrap=next((a[7:] for row in args for a in row if a.startswith('--wrap=')),'')
    if not wrap:raise RuntimeError('notification no longer uses --wrap; adapt entry-point capture to emitted script')
    exe(r/'bin/sleep','exit 0\n')
    accounting_mock(r)
    for mode in ('full','partial','empty','failed_job','fail_with_rows'):
        probe=W/('notify_'+mode);p=run(['bash','-c',wrap],renv(r,ACCOUNT_CASE=mode,ACCOUNT_PROBE=probe),r)
        check(probe.exists(),'FX-22 actual notification wrapper queried '+mode)
        check(p.returncode==0 if mode=='full' else p.returncode!=0,'FX-22 '+mode+' accounting '+('accepts complete success' if mode=='full' else 'cannot claim completion')+' (rc='+str(p.returncode)+')')


def fx21():
    r=W/'discovery';(r/'tests').mkdir(parents=True);shutil.copyfile(HW/'tests/run_tests.sh',r/'tests/run_tests.sh')
    exe(r/'tests/t01_existing.sh','echo old >> "$DISCOVERY"\n')
    exe(r/'tests/fx99_new_regression.sh','echo new >> "$DISCOVERY"; exit "${NEW_STATUS:-0}"\n')
    for status in (0,47):
        log=W/('discover_'+str(status));p=run(['bash',r/'tests/run_tests.sh'],env(DISCOVERY=log,NEW_STATUS=status),r)
        seen=log.read_text().splitlines() if log.exists() else []
        check('old' in seen,'FX-21 existing test family still executes')
        check('new' in seen,'FX-21 default runner executes newly supplied fxNN regression family')
        check(p.returncode==0 if status==0 else p.returncode!=0,'FX-21 new test '+('pass preserves suite success' if status==0 else 'failure makes suite fail')+' (rc='+str(p.returncode)+')')

def fx23():
    # Added sibling of FX-02: the NCBI helper in the *same input-fetch job*
    # has the same write-through risk at a predictable .part path.
    for mode in ('normal','partlink','curlfail'):
        r=repo('ncbi_'+mode);shared=write(r/'shared_source','precious');calls=r/'calls'
        write(r/'config/modules.sh',':\n');write(r/'config/config.sh',f'export HW="{r}" INPUT="{r}/input" RESULTS="{r}/results" LOGS_BASE="{r}/logs" PY="{r}/bin/archive_noop"\n')
        exe(r/'bin/archive_noop','echo archive_called >> "$CALLS"; exit 0\n');exe(r/'bin/git','echo git_mock >> "$CALLS"; exit 0\n');exe(r/'bin/scontrol','exit 0\n')
        pyexe(r/'bin/curl','''import os,sys
from pathlib import Path
with open(os.environ['CALLS'],'a') as f:f.write('curl '+repr(sys.argv[1:])+'\\n')
if os.environ['FAULT']=='curlfail':print('injected curl failure',file=sys.stderr);raise SystemExit(42)
a=sys.argv[1:];p=Path(a[a.index('-o')+1]);p.write_bytes(b'good')
''')
        base=r/'input/hw2/ncbi_GCA_002127715.1/GCA_002127715.1_HwerPB1_genomic.fna.gz';base.parent.mkdir(parents=True)
        write(r/'input/hw2/github_Hortaea_werneckii/.git/HEAD','fixture');write(r/'input/hw2/github_commit.txt','fixture\n')
        if mode=='partlink':Path(str(base)+'.part').symlink_to(shared)
        p=run(['bash',r/'jobs/01_fetch_inputs.sbatch'],renv(r,CALLS=calls,FAULT=mode),r)
        text=calls.read_text() if calls.exists() else '';check('archive_called' in text and 'genomic.fna.gz' in text,'FX-23 actual input job reaches NCBI curl path in '+mode)
        if mode=='curlfail':check(p.returncode!=0 and not base.exists(),'FX-23 failed NCBI download remains unpublished')
        else:
            check(p.returncode==0 and base.is_file(),'FX-23 NCBI '+mode+' download completes')
            check(shared.read_bytes()==b'precious' and not base.is_symlink(),'FX-23 NCBI '+mode+' never writes through shared .part link')

if __name__=='__main__':
    key=sys.argv[1];fn=globals().get(key)
    if not callable(fn):raise RuntimeError('unknown case '+key)
    try:fn()
    except Exception as ex:
        print('HARNESS ERROR: '+str(ex),file=sys.stderr);raise
    finish()
