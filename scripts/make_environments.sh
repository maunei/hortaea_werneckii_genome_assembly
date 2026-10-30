#!/bin/bash
# Re-creates the software environments from the explicit lock files in envs/lockfiles (each file lists the exact package builds and their checksums).
# Usage: bash scripts/make_environments.sh [NAME ...]    (no names: every environment). Needs micromamba or conda on the path; ENVS (config/config.sh) is the target folder.
# Set DRYRUN=1 to print the commands only, CHECK=1 to only test whether every environment is complete (exit code 0: yes).
# An environment is complete when the number of its packages (conda-meta/*.json) is at least the number of packages of its lock file; a folder left by a
# stopped installation has fewer, is removed and made again.
HW="${HW:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; source "$HW/config/config.sh"
MM="${MAMBA:-$(command -v micromamba || command -v conda)}"; [ -n "$MM" ] || { echo "micromamba or conda not found" >&2; exit 2; }
NAMES=("$@"); [ ${#NAMES[@]} -gt 0 ] || NAMES=($(ls "$HW/envs/lockfiles" | sed 's/\.explicit\.txt$//'))
complete() { local d="$ENVS/$1" f="$HW/envs/lockfiles/$1.explicit.txt"; [ -d "$d/conda-meta" ] && [ "$(ls "$d"/conda-meta/*.json 2>/dev/null | wc -l)" -ge "$(grep -c '^https\?://' "$f")" ]; }
if [ -n "$CHECK" ]; then for n in "${NAMES[@]}"; do complete "$n" || { echo "not complete: $ENVS/$n"; exit 1; }; done; echo "all ${#NAMES[@]} environments are complete"; exit 0; fi
mkdir -p "$ENVS"
for n in "${NAMES[@]}"; do
  cmd=("$MM" create -y -p "$ENVS/$n" --file "$HW/envs/lockfiles/$n.explicit.txt")
  if [ -n "$DRYRUN" ]; then echo "${cmd[@]}"; continue; fi
  complete "$n" && { echo "exists: $ENVS/$n"; continue; }
  [ -d "$ENVS/$n" ] && { echo "incomplete (an installation was stopped): $ENVS/$n is removed and made again"; rm -rf -- "${ENVS:?}/$n"; }
  "${cmd[@]}" || echo "FAILED: $n"
done
# compatibility library for the legacy PacBio programs (BLASR, pbdagcon were built against libnsl.so.1; the current package provides libnsl.so.3)
mkdir -p "$LEGACY_LIBS"; [ -e "$LEGACY_LIBS/libnsl.so.1" ] || ln -s "$ENVS/04_probe/lib/libnsl.so.3" "$LEGACY_LIBS/libnsl.so.1"
