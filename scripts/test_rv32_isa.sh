#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CC="${RISCV_CC:-riscv64-unknown-elf-gcc}"
OBJDUMP="${RISCV_OBJDUMP:-riscv64-unknown-elf-objdump}"
NM="${RISCV_NM:-riscv64-unknown-elf-nm}"
READELF="${RISCV_READELF:-riscv64-unknown-elf-readelf}"

TMP="$(mktemp -d /tmp/minirubik-isa.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

ELF="$TMP/solver.elf"
DISASM="$TMP/solver.disasm"

echo "========================================"
echo "MiniRubik RV32I ISA checks"
echo "========================================"

echo "[BUILD] hand-written solver as RV32I"

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
    -o "$ELF"

echo "[PASS] RV32I build"
echo

"$OBJDUMP" -d "$ELF" > "$DISASM"

echo "[CHECK] forbidden M-extension instructions"

forbidden="$(
    grep -E \
    '^[[:space:]]*[0-9a-f]+:.*[[:space:]](mul|mulh|mulhsu|mulhu|div|divu|rem|remu)([[:space:]]|$)' \
    "$DISASM" || true
)"

if [[ -n "$forbidden" ]]; then
    echo "[FAIL] forbidden instructions found:"
    echo "$forbidden"
    exit 1
fi

echo "[PASS] no mul/div/rem instructions"
echo

echo "[CHECK] compiler helper routines"

helpers="$(
    "$NM" "$ELF" |
    grep -E '__mulsi3|__divsi3|__udivsi3|__modsi3|__umodsi3' ||
    true
)"

if [[ -n "$helpers" ]]; then
    echo "[FAIL] forbidden compiler helpers found:"
    echo "$helpers"
    exit 1
fi

echo "[PASS] no multiplication/division helper routines"
echo

echo "[CHECK] ELF RISC-V architecture attribute"

arch="$(
    "$READELF" -A "$ELF" |
    sed -n 's/.*Tag_RISCV_arch: "\(.*\)"/\1/p' |
    head -n 1
)"

if [[ -z "$arch" ]]; then
    echo "[FAIL] could not read RISC-V architecture attribute"
    exit 1
fi

echo "       arch: $arch"

if [[ "$arch" != rv32i* ]]; then
    echo "[FAIL] ELF is not based on RV32I"
    exit 1
fi

echo "[PASS] RV32I architecture"
echo
echo "========================================"
echo "All RV32I ISA checks passed."
echo "========================================"
