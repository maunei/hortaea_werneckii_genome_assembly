#!/bin/bash
# FX-19: DRYRUN=1 bash scripts/make_environments.sh creates nothing on disk.
set -uo pipefail
HW="${HW:?set HW to repository root}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/micromamba" <<'M'
#!/bin/bash
mkdir -p "$4/conda-meta"   # micromamba create -y -p ENV --file LOCKFILE
for u in $(grep '^https\?://' "$6"); do touch "$4/conda-meta/$(basename "$u").json"; done
M
chmod +x "$W/bin/micromamba"

# 1. DRYRUN=1 must print commands and create nothing on disk in HW_ENVS
ENVS_DRY="$W/dry_envs"
PATH="$W/bin:$PATH" HW="$HW" HW_ENVS="$ENVS_DRY" HW_WORK="$W/w" HW_DBS="$W/d" DRYRUN=1 bash "$HW/scripts/make_environments.sh" > "$W/dry.out" 2>&1 || {
  echo "DRYRUN=1 make_environments.sh failed:"
  cat "$W/dry.out"
  exit 1
}
grep -q "create -y -p" "$W/dry.out" || { echo "DRYRUN=1 did not print create commands"; exit 1; }
if [ -e "$ENVS_DRY" ]; then
  echo "FAIL: DRYRUN=1 bash scripts/make_environments.sh created files/folders on disk: $(find "$ENVS_DRY")"
  exit 1
fi

# 2. Positive check: without DRYRUN=1, make_environments.sh creates the requested environment
ENVS_REAL="$W/real_envs"
PATH="$W/bin:$PATH" HW="$HW" HW_ENVS="$ENVS_REAL" HW_WORK="$W/w" HW_DBS="$W/d" bash "$HW/scripts/make_environments.sh" 04_probe > "$W/real.out" 2>&1 || {
  echo "real make_environments.sh failed:"
  cat "$W/real.out"
  exit 1
}
[ -d "$ENVS_REAL/04_probe/conda-meta" ] || { echo "make_environments.sh did not create 04_probe"; exit 1; }
exit 0
