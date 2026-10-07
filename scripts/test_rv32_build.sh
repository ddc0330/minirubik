#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CC="${RISCV_CC:-riscv64-unknown-elf-gcc}"
SIZE="${RISCV_SIZE:-riscv64-unknown-elf-size}"

TMP="$(mktemp -d /tmp/minirubik-rv32.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

ASM_ELF="$TMP/solver.elf"
REF_ELF="$TMP/solver_ref.elf"

echo "========================================"
echo "MiniRubik RV32 build and size tests"
echo "========================================"

echo "[BUILD] GCC -O2 RV32I reference"

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
echo

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
    -o "$ASM_ELF"

echo "[PASS] ASM build"
echo

section_size() {
    local elf="$1"
    local section="$2"

    "$SIZE" -A "$elf" |
        awk -v s="$section" '$1 == s {print $2; found=1} END {if (!found) print 0}'
}

ref_text="$(section_size "$REF_ELF" ".text")"
asm_text="$(section_size "$ASM_ELF" ".text")"

asm_rodata="$(section_size "$ASM_ELF" ".rodata")"
asm_data="$(section_size "$ASM_ELF" ".data")"
asm_bss="$(section_size "$ASM_ELF" ".bss")"

static_total=$((asm_rodata + asm_data + asm_bss))
static_limit=$((128 * 1024))

echo "[SIZE] GCC reference .text : ${ref_text} B"
echo "[SIZE] ASM           .text : ${asm_text} B"
echo

echo "[STATIC DATA]"
echo "       .rodata : ${asm_rodata} B"
echo "       .data   : ${asm_data} B"
echo "       .bss    : ${asm_bss} B"
echo "       total   : ${static_total} B"
echo "       limit   : ${static_limit} B"
echo

if (( static_total > static_limit )); then
    echo "[FAIL] static-data limit exceeded"
    exit 1
fi

echo "[PASS] static data <= 128 KiB"

if (( asm_text >= ref_text )); then
    echo "[FAIL] ASM .text (${asm_text} B) is not smaller than GCC reference (${ref_text} B)"
    exit 1
fi

echo "[PASS] ASM .text is smaller than GCC reference"
echo
echo "========================================"
echo "All RV32 build and size checks passed."
echo "========================================"
