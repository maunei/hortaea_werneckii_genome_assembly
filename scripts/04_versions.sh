#!/bin/bash
# Writes envs/versions_04.tsv: versions of the programs of steps 02, 04 and 05, read from the programs themselves (run from the package folder).
HW="${HW:-$PWD}"; source "$HW/config/config.sh"; export LD_LIBRARY_PATH="$LEGACY_LIBS:$LD_LIBRARY_PATH"
out="$HW/envs/versions_04.tsv"; printf "program\tversion\tenvironment\tpurpose\n" > "$out"
v() { printf "%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" >> "$out"; }
cm() { ls "$1/../conda-meta" | grep -E "^$2-[0-9]" | head -1 | sed -E "s/^$2-//; s/\.json$//"; }   # version of a package from the metadata of its environment
v bax2bam "$(cm "$HDF5_BIN" bax2bam) (the program prints $("$HDF5_BIN/bax2bam" --version 2>&1 | head -1))" '$HDF5_BIN' "conversion of the .bax.h5 files to subreads (step 02)"
v seqkit "$("$QC_BIN/seqkit" version 2>&1 | head -1)" '$QC_BIN' "read statistics, seed selection, FASTQ to FASTA (steps 02, 04)"
v samtools "$("$QC_BIN/samtools" --version 2>&1 | head -1)" '$QC_BIN' "BAM to FASTQ (step 02)"
v blasr "$(cm "$LEGACY_BIN" blasr)" '$LEGACY_BIN' "alignment of the reads to the seeds (step 04)"
v pbdagcon "$(cm "$LEGACY_BIN" pbdagcon)" '$LEGACY_BIN' "consensus per seed, the corrected reads (step 04)"
v Canu "$("$MODERN_BIN/canu" --version 2>&1 | head -1)" '$MODERN_BIN' "assembly of the corrected reads; control run with default settings (step 04)"
v Flye "$("$MODERN_BIN/flye" --version 2>&1 | head -1)" '$MODERN_BIN' "control assembly with default settings (step 04)"
v GenomicConsensus-Quiver "$(PATH="$LEGACY_BIN:$PATH" "$LEGACY_BIN/python" -c "import GenomicConsensus; print(GenomicConsensus.__VERSION__)" 2>&1 | tail -1)" '$LEGACY_BIN' "polishing of the contigs with Quiver (step 05)"
v pbalign "$(cm "$LEGACY_BIN" pbalign)" '$LEGACY_BIN' "alignment of the subreads with their quality tracks for Quiver (step 05)"
v Python "$("$PY" --version 2>&1)" '$PY' "scripts of steps 01, 02, 09"
cat "$out"
