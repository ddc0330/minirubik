#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CC="${RISCV_CC:-riscv64-unknown-elf-gcc}"

RIPES="${RIPES:-/mnt/c/Users/wanga/OneDrive/桌面/Ripes-v2.2.6-106-g5b8a616-win-x86_64/Ripes.exe}"

if [[ ! -f "$RIPES" ]]; then
    echo "[FAIL] Ripes not found:"
    echo "       $RIPES"
    echo
    echo "Set it manually with:"
    echo 'RIPES="/path/to/Ripes.exe" ./scripts/test_ripes_required.sh'
    exit 1
fi

TMP="$(mktemp -d /tmp/minirubik-ripes.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

REF_ELF="$TMP/solver_ref.elf"
ASM_ELF="$TMP/solver.elf"

echo "========================================"
echo "MiniRubik required-vector Ripes benchmark"
echo "========================================"

echo "[BUILD] GCC -O2 reference"

"$CC" \
    -O2 \
    -march=rv32i \
    -mabi=ilp32 \
    -ffreestanding \
    -nostdlib \
    -nostartfiles \
    -mno-relax \
    -Wl,--no-relax \
    -Wl,-e,_start \
    "$ROOT/solver_ref.c" \
    -lgcc \
    -o "$REF_ELF"

echo "[PASS] GCC reference build"

echo "[BUILD] hand-written ASM"

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
    -o "$ASM_ELF"

echo "[PASS] ASM build"
echo

run_ripes() {
    local name="$1"
    local elf="$2"
    local report="$3"

    local elf_win
    local report_win

    elf_win="$(wslpath -w "$elf")"
    report_win="$(wslpath -w "$report")"

    echo "[RIPES] $name"

    "$RIPES" \
        --mode cli \
        --src "$elf_win" \
        -t elf \
        --proc RV32_ISS \
        --iret \
        --timeout 600000 \
        --output "$report_win"

    local count

    count="$(
        awk '
            /instructions retired/ {
                getline
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                print
                exit
            }
        ' "$report"
    )"

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        echo "[FAIL] could not parse retired instruction count"
        cat "$report"
        exit 1
    fi

    printf '%s\n' "$count"
}

REF_REPORT="$TMP/ref_report.txt"
ASM_REPORT="$TMP/asm_report.txt"

ref_iret="$(run_ripes "GCC reference" "$REF_ELF" "$REF_REPORT" | tail -n 1)"
asm_iret="$(run_ripes "ASM" "$ASM_ELF" "$ASM_REPORT" | tail -n 1)"

echo
echo "[RESULT]"
printf "       GCC reference : %'d instructions\n" "$ref_iret"
printf "       ASM           : %'d instructions\n" "$asm_iret"

if (( asm_iret >= ref_iret )); then
    echo
    echo "[FAIL] ASM does not beat GCC reference in retired instructions"
    exit 1
fi

saved=$((ref_iret - asm_iret))

echo
printf "[PASS] ASM retires %'d fewer instructions than GCC\n" "$saved"

echo
echo "========================================"
echo "Required-vector Ripes benchmark passed."
echo "========================================"
