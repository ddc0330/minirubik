#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CC="${RISCV_CC:-riscv64-unknown-elf-gcc}"
SIZE="${RISCV_SIZE:-riscv64-unknown-elf-size}"

RIPES="${RIPES:-/mnt/c/Users/wanga/OneDrive/桌面/Ripes-v2.2.6-106-g5b8a616-win-x86_64/Ripes.exe}"

if [[ ! -f "$RIPES" ]]; then
    echo "[FAIL] Ripes not found:"
    echo "       $RIPES"
    exit 1
fi

TMP="$(mktemp -d /tmp/minirubik-refinement.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

V1_DIR="$TMP/v1"
mkdir -p "$V1_DIR"

V1_ELF="$TMP/solver_v1.elf"
V2_ELF="$TMP/solver_v2.elf"

echo "========================================"
echo "MiniRubik ASM refinement test"
echo "========================================"

echo "[EXTRACT] ASM v1 from commit 5631bd2"

git -C "$ROOT" show 5631bd2:solver.S > "$V1_DIR/solver.S"
git -C "$ROOT" show 5631bd2:solver_tables.S > "$V1_DIR/solver_tables.S"

echo "[PASS] extracted ASM v1"
echo

echo "[BUILD] ASM v1"

"$CC" \
    -march=rv32i \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -mno-relax \
    -Wl,--no-relax \
    -Wl,-e,_start \
    "$V1_DIR/solver.S" \
    "$V1_DIR/solver_tables.S" \
    -o "$V1_ELF"

echo "[PASS] ASM v1 build"

echo "[BUILD] ASM v2"

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
    -o "$V2_ELF"

echo "[PASS] ASM v2 build"
echo

section_size() {
    local elf="$1"
    local section="$2"

    "$SIZE" -A "$elf" |
        awk -v s="$section" '$1 == s {print $2; found=1} END {if (!found) print 0}'
}

v1_text="$(section_size "$V1_ELF" ".text")"
v2_text="$(section_size "$V2_ELF" ".text")"

echo "[CODE SIZE]"
echo "       ASM v1 .text : ${v1_text} B"
echo "       ASM v2 .text : ${v2_text} B"
echo

run_ripes() {
    local elf="$1"
    local report="$2"

    local elf_win
    local report_win
    local count

    elf_win="$(wslpath -w "$elf")"
    report_win="$(wslpath -w "$report")"

    "$RIPES" \
        --mode cli \
        --src "$elf_win" \
        -t elf \
        --proc RV32_ISS \
        --iret \
        --timeout 600000 \
        --output "$report_win" \
        >/dev/null

    count="$(
        awk '
            /instructions retired/ {
                found = 1
                next
            }

            found && $0 ~ /^[[:space:]]*[0-9]+[[:space:]]*$/ {
                gsub(/[^0-9]/, "", $0)
                print $0
                exit
            }
        ' "$report"
    )"

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        echo "[DEBUG] Could not parse report: $report" >&2
        echo "----------------------------------------" >&2
        cat "$report" >&2
        echo "----------------------------------------" >&2
        return 1
    fi

    printf '%s\n' "$count"
}

V1_REPORT="$TMP/v1_report.txt"
V2_REPORT="$TMP/v2_report.txt"

echo "[RIPES] ASM v1"
v1_iret="$(run_ripes "$V1_ELF" "$V1_REPORT")"

echo "[RIPES] ASM v2"
v2_iret="$(run_ripes "$V2_ELF" "$V2_REPORT")"

if [[ ! "$v1_iret" =~ ^[0-9]+$ || ! "$v2_iret" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] could not parse retired instruction count"
    exit 1
fi

echo
echo "[RETIRED INSTRUCTIONS]"
echo "       ASM v1 : $v1_iret"
echo "       ASM v2 : $v2_iret"
echo

if (( v2_text >= v1_text )); then
    echo "[FAIL] ASM v2 .text is not smaller than ASM v1"
    exit 1
fi

if (( v2_iret >= v1_iret )); then
    echo "[FAIL] ASM v2 does not retire fewer instructions than ASM v1"
    exit 1
fi

size_saved=$((v1_text - v2_text))
iret_saved=$((v1_iret - v2_iret))

echo "[PASS] code size reduced by ${size_saved} B"
echo "[PASS] retired instructions reduced by ${iret_saved}"
echo
echo "========================================"
echo "ASM refinement test passed."
echo "========================================"
