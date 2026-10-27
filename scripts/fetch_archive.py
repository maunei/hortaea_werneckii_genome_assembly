"""Resumable parallel download with verification of the archive checksum.
Usage: fetch.py MANIFEST.tsv DEST_DIR [WORKERS]. A file is kept when its size matches and a marker file 'NAME.md5ok' from an earlier verification exists; otherwise it is downloaded again (32 MB range requests) and verified.
Writes DEST_DIR/fetch_report.tsv (name, size, md5 expected, md5 found, seconds, status)."""
import sys, os, time, hashlib, csv, urllib.request
from concurrent.futures import ThreadPoolExecutor
man, dest = sys.argv[1], sys.argv[2]; workers = int(sys.argv[3]) if len(sys.argv) > 3 else 16
os.makedirs(dest, exist_ok=True); CH = 32 * 1024 * 1024
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
rows = list(csv.DictReader(open(man), delimiter='\t')); rep = []
for r in rows:
    d = os.path.join(dest, r['run']); os.makedirs(d, exist_ok=True); fn = os.path.join(d, r['name']); size = int(r['size']); t = time.time()
    if os.path.exists(fn) and os.path.getsize(fn) == size and os.path.exists(fn + '.md5ok'):
        rep.append((r['run'], r['name'], size, r['md5'], r['md5'], 0, 'already verified')); print(r['name'], 'already verified', flush=True); continue
    with open(fn, 'wb') as fh: fh.truncate(size)
    ch = [(o, min(o + CH, size) - 1) for o in range(0, size, CH)]
    with ThreadPoolExecutor(workers) as ex: list(ex.map(lambda c: get(r['url'], c[0], c[1], fn), ch))
    got = md5(fn); ok = got == r['md5']
    if ok: open(fn + '.md5ok', 'w').write(got + '\n')
    rep.append((r['run'], r['name'], size, r['md5'], got, round(time.time() - t), 'md5 ok' if ok else 'MD5 MISMATCH'))
    print(r['name'], size, round(time.time() - t), 's', 'md5 ok' if ok else 'MD5 MISMATCH', flush=True)
with open(os.path.join(dest, 'fetch_report.tsv'), 'a') as o:
    for x in rep: o.write('\t'.join(map(str, x)) + '\n')
sys.exit(0 if all(x[6] in ('md5 ok', 'already verified') for x in rep) else 1)
