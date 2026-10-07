#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CC="${RISCV_CC:-riscv64-unknown-elf-gcc}"
PYTHON="${PYTHON:-python3}"

RIPES="${RIPES:-/mnt/c/Users/wanga/OneDrive/桌面/Ripes-v2.2.6-106-g5b8a616-win-x86_64/Ripes.exe}"

if [[ ! -f "$RIPES" ]]; then
    echo "[FAIL] Ripes not found:"
    echo "       $RIPES"
    exit 1
fi

for file in benchmark_depth11.py depth11_states.txt solver.S solver_tables.S; do
    if [[ ! -f "$ROOT/$file" ]]; then
        echo "[FAIL] missing required file: $file"
        exit 1
    fi
done

TMP="$(mktemp -d /tmp/minirubik-depth11.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "========================================"
echo "MiniRubik distance-11 grading benchmark"
echo "========================================"

echo "[BUILD] hand-written RV32I solver"

"$CC" \
    -march=rv32i \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -mno-relax \
    -Wl,--no-relax \
    -Wl,-e,_start \
    "$ROOT/solver.S" \
    "$ROOT/solver_tables.S" \
    -o "$TMP/solver.elf"

echo "[PASS] ASM build"

cp "$ROOT/benchmark_depth11.py" "$TMP/"
cp "$ROOT/depth11_states.txt" "$TMP/"

echo
echo "[TEST] all 2,644 distance-11 states"
echo "       grading limit: 50,000,000 retired instructions/state"
echo "       this can take a long time..."
echo

cd "$TMP"

"$PYTHON" benchmark_depth11.py \
    --ripes "$RIPES" |
    tee benchmark_output.txt

completed="$(
    sed -n 's/^completed[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
        benchmark_output.txt |
    tail -n 1
)"

over="$(
    sed -n 's/^over 50M[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
        benchmark_output.txt |
    tail -n 1
)"

maximum="$(
    sed -n 's/^maximum[[:space:]]*:[[:space:]]*\([0-9,]*\).*/\1/p' \
        benchmark_output.txt |
    tail -n 1 |
    tr -d ','
)"

worst="$(
    sed -n 's/^worst[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
        benchmark_output.txt |
    tail -n 1
)"

required="$(
    sed -n 's/^required[[:space:]]*:[[:space:]]*21345671111111 -> \([0-9,]*\).*/\1/p' \
        benchmark_output.txt |
    tail -n 1 |
    tr -d ','
)"

if [[ "$completed" != "2644" ]]; then
    echo
    echo "[FAIL] expected 2644 completed states, got ${completed:-unknown}"
    exit 1
fi

if [[ "$over" != "0" ]]; then
    echo
    echo "[FAIL] ${over:-unknown} states exceeded 50,000,000 instructions"
    exit 1
fi

if [[ ! "$maximum" =~ ^[0-9]+$ ]] || (( maximum > 50000000 )); then
    echo
    echo "[FAIL] invalid or excessive worst-case instruction count"
    exit 1
fi

if [[ ! "$required" =~ ^[0-9]+$ ]]; then
    echo
    echo "[FAIL] required-vector result missing"
    exit 1
fi

echo
echo "========================================"
echo "Distance-11 benchmark summary"
echo "========================================"
echo "states tested    : $completed"
echo "worst state      : $worst"
echo "maximum --iret   : $maximum"
echo "required --iret  : $required"
echo "states over 50M  : $over"
echo
echo "[PASS] all 2,644 distance-11 states satisfy the grading limit"
echo "========================================"
