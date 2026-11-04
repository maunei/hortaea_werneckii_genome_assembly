#!/bin/bash
# FX-55 (D-01): scripts/09_resources.py refuses the table when sacct returns an unexpanded
# bracketed array range (e.g. 7002_[0-2] on a job with want is None, or 7001_[2-3] alongside
# completed tasks 7001_0 and 7001_1 of an array job).
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:-$(cd "$(dirname "$0")/.." && pwd)}"
PY="${PY:-python3}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/bin" "$W/hw/jobs" "$W/hw/results" "$W/hw/logs"
printf '#!/bin/bash\n#SBATCH --array=0-1\n' > "$W/hw/jobs/h.sbatch"
printf '#!/bin/bash\n#SBATCH -J plain\n' > "$W/hw/jobs/n.sbatch"
printf 'arr\t7001\t\th.sbatch\t\nplain\t7002\t\tn.sbatch\t\n' > "$W/hw/jobs/submitted_by_submit_all.tsv"

cat > "$W/bin/sacct" <<'EOF'
#!/bin/bash
row() { echo "$1|$2|${3:-COMPLETED}|01:00:00|02:00:00|4|"; }
case "${CASE:-}" in
  ok)
    row 7001_0 7011
    row 7001_1 7012
    row 7002 7002
    ;;
  plain_bracketed)
    row 7001_0 7011
    row 7001_1 7012
    row "7002_[0-2]" 7002
    ;;
  array_extra_bracketed)
    row 7001_0 7011
    row 7001_1 7012
    row "7001_[2-3]" 7001 CANCELLED
    row 7002 7002
    ;;
esac
EOF
chmod +x "$W/bin/sacct"

for c in ok plain_bracketed array_extra_bracketed; do
  rm -rf "$W/hw/results/09_summary"
  rc=0
  CASE="$c" PATH="$W/bin:$PATH" HW="$W/hw" python3 "$HW/scripts/09_resources.py" > "$W/$c.out" 2>&1 || rc=$?
  if [ "$c" = "ok" ]; then
    [ "$rc" -eq 0 ] && [ -s "$W/hw/results/09_summary/resources_totals.json" ] || {
      echo "FAIL: 09_resources.py failed on valid unbracketed accounting (rc=$rc)" >&2
      cat "$W/$c.out" >&2
      exit 1
    }
  else
    [ "$rc" -ne 0 ] && [ ! -e "$W/hw/results/09_summary/resources_totals.json" ] || {
      echo "FAIL: 09_resources.py accepted unexpanded bracketed array range in case '$c' (rc=$rc)" >&2
      cat "$W/$c.out" >&2
      exit 1
    }
    grep -q "unexpanded array range in accounting" "$W/$c.out" || {
      echo "FAIL: missing 'unexpanded array range in accounting' error message in case '$c': $(cat "$W/$c.out")" >&2
      exit 1
    }
  fi
done

echo "PASS"
