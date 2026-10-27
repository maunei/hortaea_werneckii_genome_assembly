#!/bin/bash
#SBATCH --job-name=hw_01_check_inputs
#SBATCH --account=<ACCOUNT>
#SBATCH --time=02:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=8
#SBATCH --output=logs/%x_%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=<ADDRESS>

module --force purge
module load StdEnv/2023
HW="${SLURM_SUBMIT_DIR:-$PWD}"; source "$HW/config/config.sh"; source "$HW/config/lib.sh"
hw_start 01_check_inputs

# Verification of the input files: (1) every file against the list of checksums kept in the input folder, (2) the archive files against the
# checksums of the archive records (manifests). Output: results/01_inputs/input_check.tsv and archive_check.tsv.
mkdir -p "$RESULTS/01_inputs"; cd "$INPUT"
# (1) file by file
md5sum -c --quiet CHECKSUMS.md5 > "$RESULTS/01_inputs/checksums_failed.txt" 2>&1; rc1=$?
echo "files in the list: $(wc -l < CHECKSUMS.md5); failed: $(grep -c FAILED "$RESULTS/01_inputs/checksums_failed.txt")"
# (2) archive checksums
$PY - <<PYEOF
import csv, os
inp = os.environ['INPUT']; res = os.environ['RESULTS'] + '/01_inputs'
md5 = {}
for l in open(inp + '/CHECKSUMS.md5'):
    h, p = l.rstrip('\n').split('  ', 1); md5[p.lstrip('./')] = h
rows = []
for man, sub, layout in (('pacbio_files.tsv', 'pacbio', 'run/name'), ('rna_sra_files.tsv', 'rnaseq', 'run/run'), ('illumina2013_sra_files.tsv', 'illumina2013', 'run/run')):
    for r in csv.DictReader(open(f'{inp}/manifests/{man}'), delimiter='\t'):
        p = f"{sub}/{r['run']}/{r['name']}" if layout == 'run/name' else f"{sub}/{r['run']}/{r['name']}"
        got = md5.get(p); rows.append((sub, r['run'], r['name'], r['size'], r['md5'], got or 'missing', 'ok' if got == r['md5'] else 'DIFFERENT'))
with open(res + '/archive_check.tsv', 'w') as w:
    w.write('group\trun\tfile\tsize\tmd5_archive\tmd5_found\tstatus\n')
    for x in rows: w.write('\t'.join(map(str, x)) + '\n')
print('archive files:', len(rows), ' ok:', sum(1 for x in rows if x[-1] == 'ok'))
PYEOF
hw_end 01_check_inputs
exit $rc1
