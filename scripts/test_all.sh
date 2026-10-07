#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-quick}"

run_test() {
    local script="$1"

    echo
    echo "========================================"
    echo "Running: $script"
    echo "========================================"

    "$ROOT/scripts/$script"
}

case "$MODE" in
    quick)
        echo "MiniRubik quick test suite"

        run_test test_c_basic.sh
        run_test test_rv32_build.sh
        run_test test_ripes_required.sh
        run_test test_asm_refinement.sh
        run_test test_rv32_isa.sh
        ;;

    full)
        echo "MiniRubik full test suite"

        run_test test_c_basic.sh
        run_test test_c_exhaustive.sh
        run_test test_rv32_build.sh
        run_test test_ripes_required.sh
        run_test test_asm_refinement.sh
        run_test test_rv32_isa.sh
        run_test test_depth11_all.sh
        ;;

    *)
        echo "Usage:"
        echo "  $0 quick"
        echo "  $0 full"
        exit 1
        ;;
esac

echo
echo "========================================"
echo "All ${MODE} tests passed."
echo "========================================"
