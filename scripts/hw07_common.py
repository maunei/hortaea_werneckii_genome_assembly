"""Helpers shared by the scripts of step 07: FASTA reading, GC content, alignment (PAF) parsing, interval union, depth tables."""
import gzip, hashlib, json, os, re, subprocess, sys
from collections import defaultdict

def read_fasta(path):
    """Return an ordered dict name -> sequence (name = first word of the header)."""
    op = gzip.open if str(path).endswith(".gz") else open
    d, name, buf = {}, None, []
    with op(path, "rt") as f:
        for line in f:
            if line.startswith(">"):
                if name is not None: d[name] = "".join(buf)
                name = line[1:].split()[0]; buf = []
            else:
                buf.append(line.strip())
    if name is not None: d[name] = "".join(buf)
    return d

def write_fasta(path, seqs, width=80):
    with open(path, "w") as o:
        for k, s in seqs.items():
            o.write(f">{k}\n")
            for i in range(0, len(s), width): o.write(s[i:i + width] + "\n")

def md5(s): return hashlib.md5(s.encode()).hexdigest()

def gc_fraction(s):
    """GC fraction over A, C, G and T bases (case-insensitive); N and other symbols are ignored."""
    u = s.upper(); a = u.count("A"); c = u.count("C"); g = u.count("G"); t = u.count("T")
    return (g + c) / (a + c + g + t) if (a + c + g + t) else float("nan")

def union_length(intervals):
    """Total length covered by a list of (start, end) intervals (half-open)."""
    tot, cur_s, cur_e = 0, None, None
    for s, e in sorted(intervals):
        if cur_e is None or s > cur_e:
            if cur_e is not None: tot += cur_e - cur_s
            cur_s, cur_e = s, e
        else:
            cur_e = max(cur_e, e)
    if cur_e is not None: tot += cur_e - cur_s
    return tot

PAF_COLS = ["qname", "qlen", "qstart", "qend", "strand", "tname", "tlen", "tstart", "tend", "nmatch", "alnlen", "mapq"]
def read_paf(path):
    """List of dicts (first 12 PAF columns plus tags)."""
    rows = []
    with open(path) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 12: continue
            r = dict(zip(PAF_COLS, p[:12]))
            for k in ("qlen", "qstart", "qend", "tlen", "tstart", "tend", "nmatch", "alnlen", "mapq"): r[k] = int(r[k])
            r["tags"] = {t.split(":")[0]: t.split(":", 2)[2] for t in p[12:]}
            rows.append(r)
    return rows

CS_RE = re.compile(r"(:[0-9]+|\*[acgtn][acgtn]|[+-][acgtn]+)")
def cs_counts(cs):
    """Substitutions, inserted and deleted bases and indel events from a minimap2 'cs' long string (query relative to target)."""
    sub = ins = dele = nins = ndel = match = 0
    for m in CS_RE.findall(cs):
        if m[0] == ":": match += int(m[1:])
        elif m[0] == "*": sub += 1
        elif m[0] == "+": ins += len(m) - 1; nins += 1
        elif m[0] == "-": dele += len(m) - 1; ndel += 1
    return dict(match=match, substitutions=sub, inserted_bases=ins, deleted_bases=dele, insertion_events=nins, deletion_events=ndel)

def run(cmd, **kw):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), check=True, capture_output=True, text=True, **kw)
    return r.stdout

def read_window_depth(path):
    """mosdepth regions.bed(.gz): returns list of (contig, start, end, mean_depth)."""
    op = gzip.open if str(path).endswith(".gz") else open
    out = []
    with op(path, "rt") as f:
        for line in f:
            c, s, e, d = line.split("\t")[:4]
            out.append((c, int(s), int(e), float(d)))
    return out

def nuclear_median(windows, exclude_contigs, min_contig_len=20000, window=1000):
    """Median of the mean depth of complete windows of the contigs that are not excluded and are at least min_contig_len long."""
    import statistics
    ln = defaultdict(int)
    for c, s, e, d in windows: ln[c] = max(ln[c], e)
    vals = [d for c, s, e, d in windows if c not in exclude_contigs and ln[c] >= min_contig_len and e - s == window]
    return statistics.median(vals) if vals else float("nan")
