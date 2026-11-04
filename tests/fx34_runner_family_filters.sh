#!/bin/bash
# FX-34 (B-08): tests/run_tests.sh filter behavior:
#   t03  -> runs only t03*.sh (never fx03*.sh)
#   fx03 -> runs only fx03*.sh (never t03*.sh)
#   03   -> runs both t03*.sh and fx03*.sh
set -euo pipefail
unset PYTHONSAFEPATH
export LC_ALL=C

HW="${HW:?set HW to the repository root}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/tests"
cp "$HW/tests/run_tests.sh" "$W/tests/run_tests.sh"

for name in t03_alpha t04_beta fx03_one fx03_two fx04_other; do
  cat > "$W/tests/${name}.sh" <<EOF
#!/bin/bash
echo "$name" >> "\$RAN_LOG"
exit 0
EOF
  chmod +x "$W/tests/${name}.sh"
done

check_filter() {
  local filt="$1" expected="$2"
  export RAN_LOG="$W/ran_${filt}.log"
  : > "$RAN_LOG"
  bash "$W/tests/run_tests.sh" "$filt" > "$W/out_${filt}.txt" 2>&1 || {
    echo "FAIL: run_tests.sh $filt exited non-zero" >&2
    cat "$W/out_${filt}.txt" >&2
    exit 1
  }
  local got
  got="$(paste -sd, "$RAN_LOG")"
  [ "$got" = "$expected" ] || {
    echo "FAIL: filter '$filt' ran [$got], expected [$expected]" >&2
    exit 1
  }
}

check_filter "t03" "t03_alpha"
check_filter "fx03" "fx03_one,fx03_two"
check_filter "03" "t03_alpha,fx03_one,fx03_two"
check_filter "fx03_two.sh" "fx03_two"

echo "PASS"
