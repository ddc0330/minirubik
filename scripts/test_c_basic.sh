#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-gcc}"

BIN="$(mktemp /tmp/minirubik-c-basic.XXXXXX)"
trap 'rm -f "$BIN"' EXIT

echo "========================================"
echo "MiniRubik C basic tests"
echo "========================================"

echo "[BUILD] Stage 3 C solver"

"$CC" \
    -O2 \
    -std=c11 \
    -Wall \
    -Wextra \
    -DSOLVER_STATE_MAJOR \
    -DSOLVER_STATS \
    "$ROOT/solver.c" \
    -o "$BIN"

echo "[PASS] build"
echo

run_case() {
    local name="$1"
    local input="$2"
    local expected_depth="$3"
    local expected_solution="${4:-}"

    local output
    local depth
    local stats
    local solution

    echo "[TEST] $name"
    echo "       input: $input"

    if ! output="$("$BIN" "$input" 2>&1)"; then
        echo "[FAIL] solver exited with an error"
        echo "$output"
        exit 1
    fi

    depth="$(
        printf '%s\n' "$output" |
        sed -n 's/.*solution_depth=\([-0-9][0-9]*\).*/\1/p' |
        head -n 1
    )"

    if [[ "$depth" != "$expected_depth" ]]; then
        echo "[FAIL] expected depth $expected_depth, got ${depth:-unknown}"
        echo "$output"
        exit 1
    fi

    if [[ -n "$expected_solution" ]]; then
        solution="$(printf '%s\n' "$output" | tail -n 1)"

        if [[ "$solution" != "$expected_solution" ]]; then
            echo "[FAIL] expected solution '$expected_solution', got '$solution'"
            echo "$output"
            exit 1
        fi
    fi

    stats="$(printf '%s\n' "$output" | grep -m1 '^rank=' || true)"

    echo "[PASS] depth = $depth"

    if [[ -n "$stats" ]]; then
        echo "       $stats"
    fi

    echo
}

run_case "Solved cube" \
    "12345671111111" \
    "0"

run_case "One-move scramble" \
    "25314672313211" \
    "1" \
    "R'"

run_case "Required distance-11 vector" \
    "21345671111111" \
    "11"

echo "========================================"
echo "All C basic tests passed."
echo "========================================"
