"""Resumable parallel download with verification of the archive checksum.
Usage: fetch.py MANIFEST.tsv DEST_DIR [WORKERS]. A file is kept when its size matches and its marker file 'NAME.md5ok' holds the expected checksum (a marker with another content is not trusted: the file is checked again); otherwise it is downloaded again (32 MB range requests, into a new temporary file of the same folder) and verified.
Writes DEST_DIR/fetch_report.tsv (name, size, md5 expected, md5 found, seconds, status)."""
import sys, os, glob, fcntl, time, hashlib, csv, tempfile, urllib.request
from concurrent.futures import ThreadPoolExecutor
man, dest = sys.argv[1], sys.argv[2]; workers = int(sys.argv[3]) if len(sys.argv) > 3 else 16
os.makedirs(dest, exist_ok=True); CH = 32 * 1024 * 1024
try: LOCK = open(os.path.join(dest, '.fetch.lock'), 'a'); fcntl.flock(LOCK, fcntl.LOCK_EX)   # one downloader per folder at a time (a second one waits): no two processes write the same final file, marker or report, and every unfinished NAME.*.part file found below is the remains of a process that has ended
except OSError as e: print('ERROR: the lock of the folder could not be taken:', e, file=sys.stderr); sys.exit(2)
def get(link, off, end, fn):
    for k in range(8):
        try:
            r = urllib.request.urlopen(urllib.request.Request(link, headers={'Range': f'bytes={off}-{end}'}), timeout=120); data = r.read()
            if len(data) != end - off + 1: raise IOError('short read')
            with open(fn, 'r+b') as f: f.seek(off); f.write(data)
            return len(data)
        except Exception as e:
            time.sleep(2 + 3 * k)
    raise RuntimeError(f'chunk {off} failed')
def md5(fn):
    h = hashlib.md5()
    with open(fn, 'rb') as f:
        for b in iter(lambda: f.read(16 * 1024 * 1024), b''): h.update(b)
    return h.hexdigest()
UMASK = os.umask(0); os.umask(UMASK)
def marker_ok(fn, expected):   # the marker is trusted only when it holds the expected checksum
    try: return open(fn + '.md5ok').read().strip() == expected
    except OSError: return False
def replace_text(path, text, keep=''):   # writes a new file in the same folder and renames it over the old name: a link or a second name of the old file is never written through
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or '.', prefix=os.path.basename(path) + '.', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as o: o.write(keep + text)
        os.chmod(tmp, 0o666 & ~UMASK); os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise
def write_marker(fn, got):
    try: replace_text(fn + '.md5ok', got + '\n')
    except OSError: pass
def drop(fn):   # a file that is not what the archive holds must not stay under its final name (a link is removed, never followed)
    for x in (fn, fn + '.md5ok'):
        try: os.unlink(x)
        except OSError: pass
rows = list(csv.DictReader(open(man), delimiter='\t')); rep = []
for r in rows:
    d = os.path.join(dest, r['run']); os.makedirs(d, exist_ok=True); fn = os.path.join(d, r['name']); size = int(r['size']); t = time.time()
    if os.path.exists(fn) and os.path.getsize(fn) == size:
        if marker_ok(fn, r['md5']):
            rep.append((r['run'], r['name'], size, r['md5'], r['md5'], 0, 'already verified')); print(r['name'], 'already verified', flush=True); continue
        got = md5(fn)
        if got == r['md5']:
            write_marker(fn, got)
            rep.append((r['run'], r['name'], size, r['md5'], got, round(time.time() - t), 'already verified')); print(r['name'], 'verified existing file', flush=True); continue
    # download into a new, uniquely named file of the same folder (created exclusively: an existing file or link of any name is never opened)
    for old in glob.glob(glob.escape(os.path.join(d, r['name'])) + '.*.part'):   # the unfinished download of an earlier attempt that was stopped (time limit): removed (the lock above is held, so no other downloader of this folder is running)
        try: os.unlink(old)
        except OSError: pass
    fd, part = tempfile.mkstemp(prefix=r['name'] + '.', suffix='.part', dir=d)
    try:
        try: os.ftruncate(fd, size); os.fchmod(fd, 0o666 & ~UMASK)
        finally: os.close(fd)   # the mode of an ordinary new file (mkstemp makes it private)
        ch = [(o, min(o + CH, size) - 1) for o in range(0, size, CH)]
        with ThreadPoolExecutor(workers) as ex: list(ex.map(lambda c: get(r['url'], c[0], c[1], part), ch))
        got = md5(part); ok = got == r['md5']
    except Exception as e:
        got = 'download failed: ' + str(e)[:60]; ok = False
    if ok:
        if os.path.islink(fn): os.unlink(fn)   # a link into input_source is replaced by the file, never written through
        if os.path.islink(fn + '.md5ok'): os.unlink(fn + '.md5ok')
        os.replace(part, fn); write_marker(fn, got)
    else:
        try: os.remove(part)
        except OSError: pass
        drop(fn)   # the file under the final name is not the archive file
    rep.append((r['run'], r['name'], size, r['md5'], got, round(time.time() - t), 'md5 ok' if ok else 'MD5 MISMATCH' if not got.startswith('download failed') else 'DOWNLOAD FAILED'))
    print(r['name'], size, round(time.time() - t), 's', rep[-1][-1], flush=True)
report = os.path.join(dest, 'fetch_report.tsv')
try: old_report = open(report).read()
except FileNotFoundError: old_report = ''
except OSError as e: old_report = None; print('WARNING: the report', report, 'cannot be read and is left as it is:', e, file=sys.stderr)   # the earlier rows are never discarded
if old_report is not None:
    try: replace_text(report, ''.join('\t'.join(map(str, x)) + '\n' for x in rep), old_report)   # the earlier rows are kept; the file is replaced, never written through a link
    except OSError as e: print('WARNING: the report', report, 'was not written:', e, file=sys.stderr)
sys.exit(0 if all(x[6] in ('md5 ok', 'already verified') for x in rep) else 1)
