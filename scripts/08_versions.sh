#!/bin/bash
# Writes envs/versions_08.tsv: versions of the programs of step 08, read from the programs themselves.
HW="${HW:-$PWD}"; source "$HW/config/config.sh"
out="$HW/envs/versions_08.tsv"
{
printf 'program\tversion\tenvironment\tpurpose\n'
printf 'bwa\t%s\t$VAR_BIN\tindex and mapping of the Illumina read pairs (bwa-mem)\n' "$("$VAR_BIN/bwa" 2>&1 | awk '/^Version/{print $2}')"
printf 'samtools\t%s\t$VAR_BIN\tsorting, index, flagstat, stats, read counts\n' "$("$VAR_BIN/samtools" --version | awk 'NR==1{print $2}')"
printf 'bcftools\t%s\t$VAR_BIN\tmpileup, haploid calling, normalisation, filtering of the differences\n' "$("$VAR_BIN/bcftools" --version | awk 'NR==1{print $2}')"
printf 'mosdepth\t%s\t$VAR_BIN\tdepth in windows of 1 kb, callable positions\n' "$("$VAR_BIN/mosdepth" --version | awk '{print $2}')"
printf 'python\t%s\t$PY\tsummary tables, arrangement of differences, shared differences\n' "$("$PY" -c 'import platform; print(platform.python_version())')"
printf 'numpy\t%s\t$PY\trandom scatter of differences, window counts\n' "$("$PY" -c 'import numpy; print(numpy.__version__)')"
} > "$out"
cat "$out"
