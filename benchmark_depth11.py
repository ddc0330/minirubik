#!/usr/bin/env python3

import argparse
import csv
import re
import subprocess
from pathlib import Path

BASE_INPUT = b"21345671111111"
THRESHOLD = 50_000_000

BASE_ELF = Path("solver.elf").resolve()
STATES_FILE = Path("depth11_states.txt").resolve()
TEMP_ELF = Path("solver_bench.elf").resolve()
REPORT = Path("ripes_bench_report.txt").resolve()
CSV_FILE = Path("depth11_iret.csv").resolve()


def windows_path(path):
    return subprocess.check_output(
        ["wslpath", "-w", str(path)],
        text=True
    ).strip()


def load_states():
    states = [
        line.strip()
        for line in STATES_FILE.read_text().splitlines()
        if line.strip()
    ]

    if len(states) != 2644:
        raise RuntimeError(
            f"expected 2644 states, found {len(states)}"
        )

    for state in states:
        if len(state) != 14 or not state.isdigit():
            raise RuntimeError(f"invalid state: {state}")

    if "21345671111111" not in states:
        raise RuntimeError("required vector missing")

    return states


def locate_input(base):
    positions = []
    start = 0

    while True:
        pos = base.find(BASE_INPUT, start)

        if pos < 0:
            break

        positions.append(pos)
        start = pos + 1

    if len(positions) != 1:
        raise RuntimeError(
            f"expected exactly one embedded input, found {len(positions)}"
        )

    return positions[0]


def load_existing_results():
    results = {}

    if not CSV_FILE.exists():
        return results

    with CSV_FILE.open(newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            results[row["state"]] = int(row["iret"])

    return results


def append_result(index, state, iret):
    exists = CSV_FILE.exists()

    with CSV_FILE.open("a", newline="") as f:
        writer = csv.writer(f)

        if not exists:
            writer.writerow(["index", "state", "iret"])

        writer.writerow([index, state, iret])


def run_ripes(ripes, win_elf, win_report):
    if REPORT.exists():
        REPORT.unlink()

    subprocess.run(
        [
            str(ripes),
            "--mode", "cli",
            "--src", win_elf,
            "-t", "elf",
            "--proc", "RV32_ISS",
            "--iret",
            "--timeout", "600000",
            "--output", win_report,
        ],
        check=True,
    )

    text = REPORT.read_text()

    match = re.search(
        r"instructions retired\s+(\d+)",
        text
    )

    if not match:
        raise RuntimeError(
            "could not parse retired instruction count:\n" + text
        )

    return int(match.group(1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="only run the first N unfinished states"
    )
    parser.add_argument(
        "--ripes",
        type=Path,
        required=True,
        help="path to the pinned Ripes.exe"
    )
    args = parser.parse_args()

    ripes = args.ripes.resolve()

    if not ripes.exists():
        raise RuntimeError(f"Ripes not found: {ripes}")

    states = load_states()

    base = BASE_ELF.read_bytes()
    input_offset = locate_input(base)

    print(f"states: {len(states)}")
    print(f"input ELF offset: {input_offset}")
    print(f"threshold: {THRESHOLD:,}")

    existing = load_existing_results()

    if existing:
        print(f"resuming with {len(existing)} completed states")

    win_elf = windows_path(TEMP_ELF)
    win_report = windows_path(REPORT)

    newly_run = 0

    for index, state in enumerate(states, start=1):
        if state in existing:
            continue

        patched = bytearray(base)

        patched[
            input_offset:input_offset + 14
        ] = state.encode("ascii")

        TEMP_ELF.write_bytes(patched)

        iret = run_ripes(ripes, win_elf, win_report)

        append_result(index, state, iret)
        existing[state] = iret

        newly_run += 1

        current_max_state = max(
            existing,
            key=existing.get
        )
        current_max = existing[current_max_state]

        status = "PASS"
        if iret > THRESHOLD:
            status = "OVER LIMIT"

        print(
            f"[{index:4d}/2644] "
            f"{state}  "
            f"{iret:>10,}  "
            f"{status}  "
            f"current max={current_max:,} "
            f"({current_max_state})",
            flush=True,
        )

        if args.limit is not None and newly_run >= args.limit:
            break

    if not existing:
        return

    values = list(existing.values())

    worst_state = max(existing, key=existing.get)
    worst = existing[worst_state]

    required = existing.get("21345671111111")

    over = [
        (state, count)
        for state, count in existing.items()
        if count > THRESHOLD
    ]

    print()
    print("===== summary =====")
    print(f"completed : {len(existing)} / 2644")
    print(f"minimum   : {min(values):,}")
    print(f"average   : {sum(values) / len(values):,.2f}")
    print(f"maximum   : {worst:,}")
    print(f"worst     : {worst_state}")
    print(f"over 50M  : {len(over)}")

    if required is not None:
        print(
            f"required   : "
            f"21345671111111 -> {required:,}"
        )

    if len(existing) == 2644:
        if over:
            print("RESULT     : FAIL worst-case requirement")
        else:
            print("RESULT     : PASS worst-case requirement")


if __name__ == "__main__":
    main()