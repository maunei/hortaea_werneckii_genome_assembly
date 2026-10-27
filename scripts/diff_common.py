"""Helpers shared by the scripts of step 08 (differences between Illumina reads and an assembly).

A difference is described by the first base it touches (0-based), the assembly sequence it replaces (refseq) and the
sequence the reads carry instead (altseq). Single-base difference: both of length 1. Insertion: refseq empty.
Deletion: altseq empty. The common leading and trailing bases of the two VCF alleles are removed so that the
description does not depend on how an indel is anchored.
"""
COMP = str.maketrans("ACGTNacgtn", "TGCANtgcan")


def revcomp(s):
    return s.translate(COMP)[::-1]


def read_fasta(path):
    """Return {name: upper-case sequence}; the name is the first word of the header."""
    seqs, name, buf = {}, None, []
    with open(path) as fh:
        for line in fh:
            if line.startswith(">"):
                if name is not None:
                    seqs[name] = "".join(buf)
                name, buf = line[1:].split()[0], []
            else:
                buf.append(line.strip().upper())
    if name is not None:
        seqs[name] = "".join(buf)
    return seqs


def trim_event(pos1, ref, alt):
    """VCF record (1-based pos, alleles) -> (start0, refseq, altseq) after removing the common prefix and suffix."""
    p = 0
    while p < len(ref) and p < len(alt) and ref[p] == alt[p]:
        p += 1
    ref, alt = ref[p:], alt[p:]
    while ref and alt and ref[-1] == alt[-1]:
        ref, alt = ref[:-1], alt[:-1]
    return pos1 - 1 + p, ref, alt


def event_class(refseq, altseq):
    if len(refseq) == 1 and len(altseq) == 1:
        return "snv"
    if not refseq and altseq:
        return "ins"
    if refseq and not altseq:
        return "del"
    return "complex"


def run_length(seq, start0, end0, base):
    """Length of the run of `base` that contains the interval [start0, end0) (end0 == start0 for an insertion point)."""
    i = start0
    while i > 0 and seq[i - 1] == base:
        i -= 1
    j = end0
    n = len(seq)
    while j < n and seq[j] == base:
        j += 1
    return j - i


def indel_context(seq, start0, refseq, altseq, min_run=3):
    """For an insertion or deletion: (homopolymer?, run length). The event is in a homopolymer when the inserted or
    deleted sequence is a single repeated base and the assembly holds a run of at least `min_run` of that base at the site."""
    s = altseq if not refseq else refseq
    if not s or len(set(s)) != 1:
        return False, 0
    b = s[0]
    end0 = start0 + len(refseq)
    r = run_length(seq, start0, end0, b)
    return r >= min_run, r


def event_key(seq, start0, refseq, altseq, flank=20):
    """Orientation-independent description of the event with `flank` assembly bases on each side, or None when the
    window leaves the contig or contains an N. For a single-base difference the window has 2*flank+1 bases."""
    a, b = start0 - flank, start0 + len(refseq) + flank
    if a < 0 or b > len(seq):
        return None
    left, right = seq[a:start0], seq[start0 + len(refseq):b]
    if "N" in left or "N" in right or "N" in refseq or "N" in altseq:
        return None
    fwd = (left, refseq, altseq, right)
    rev = (revcomp(right), revcomp(refseq), revcomp(altseq), revcomp(left))
    return min(fwd, rev)
