#!/bin/bash
# FX-43: (d) fetch_ncbi() in jobs/01_fetch_inputs.sbatch removes stale $dst.*.part files
# before downloading into a fresh mktemp $dst.XXXXXX.part file, and removes its temporary file on curl failure.
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/bin" "$W/ncbi"
sed -n '/^fetch_ncbi()/,/^}/p' "$HW/jobs/01_fetch_inputs.sbatch" > "$W/fetch_ncbi.sh"
[ -s "$W/fetch_ncbi.sh" ] || { echo "FAIL: fetch_ncbi() not found in jobs/01_fetch_inputs.sbatch" >&2; exit 1; }

cat > "$W/bin/curl" <<'EOF'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "${MOCK_CURL_FAIL:-0}" = "1" ]; then
  printf 'partial_failed_download' > "$out"
  exit 22
fi
printf 'valid_ncbi_payload\n' > "$out"
exit 0
EOF
chmod +x "$W/bin/curl"

# shellcheck disable=SC1090
source "$W/fetch_ncbi.sh"

DST="$W/ncbi/GCA_002127715.1_HwerPB1_genomic.fna.gz"
STALE1="$DST.old111.part"
STALE2="$DST.old222.part"
printf 'stale1' > "$STALE1"
printf 'stale2' > "$STALE2"

# 1. Successful download removes pre-existing stale .part files and installs dst
PATH="$W/bin:$PATH" fetch_ncbi "$DST" "https://example.org/genomic.fna.gz"
[ -s "$DST" ] || { echo "FAIL: fetch_ncbi did not create $DST" >&2; exit 1; }
[ ! -e "$STALE1" ] && [ ! -e "$STALE2" ] || { echo "FAIL: fetch_ncbi left stale .part files behind" >&2; exit 1; }
compgen -G "$DST.*.part" >/dev/null && { echo "FAIL: leftover .part file after successful fetch_ncbi" >&2; exit 1; }

# 2. Failed download removes both pre-existing stale .part files and new tmp .part file, and exits 6
DST2="$W/ncbi/README.txt"
printf 'stale3' > "$DST2.old333.part"
rc=0
( PATH="$W/bin:$PATH" MOCK_CURL_FAIL=1 fetch_ncbi "$DST2" "https://example.org/README.txt" ) >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 6 ] || { echo "FAIL: expected exit 6 from fetch_ncbi on curl failure, got $rc" >&2; exit 1; }
[ ! -e "$DST2" ] || { echo "FAIL: failed fetch_ncbi left $DST2" >&2; exit 1; }
compgen -G "$DST2.*.part" >/dev/null && { echo "FAIL: failed fetch_ncbi left .part file(s) behind" >&2; exit 1; }

echo "PASS"
