#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-gcc}"

BIN="$(mktemp /tmp/minirubik-c-exhaustive.XXXXXX)"
trap 'rm -f "$BIN"' EXIT

echo "========================================"
echo "MiniRubik C exhaustive verification"
echo "========================================"

echo "[BUILD] host verifier"

"$CC" \
    -O2 \
    -std=c11 \
    -Wall \
    -Wextra \
    -DSOLVER_STATE_MAJOR \
    -DSOLVER_HOST_VERIFY \
    "$ROOT/solver.c" \
    -o "$BIN"

echo "[PASS] build"
echo
echo "[TEST] all 3,674,160 reachable states"
echo "       this may take a few minutes..."

start=$(date +%s)

output="$("$BIN" --self-test 2>&1)"

end=$(date +%s)
elapsed=$((end - start))

printf '%s\n' "$output"

required=(
    "3674160 states"
    "diameter 11"
    "admissibility checked"
    "all 3674160 optimal solutions replayed"
    "2644 distance-11 states and test vector verified"
    "linked constants match regenerated tables"
)

for expected in "${required[@]}"; do
    if ! grep -Fq "$expected" <<< "$output"; then
        echo
        echo "[FAIL] missing expected result:"
        echo "       $expected"
        exit 1
    fi
done

echo
echo "[PASS] exhaustive verification"
echo "       elapsed: ${elapsed}s"
echo
echo "========================================"
echo "All exhaustive C checks passed."
echo "========================================"
