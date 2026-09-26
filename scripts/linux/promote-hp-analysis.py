#!/usr/bin/env python3
"""Review or merge HP INF findings into the curated candidate TSVs."""

import argparse
import csv
import os
from pathlib import Path
import tempfile


HARDWARE_COLUMNS = ("hardware_id", "provider", "inf_source", "evidence")
FIRMWARE_COLUMNS = ("firmware_name", "inf_source", "evidence")


def parse_manifest(path):
    hardware = set()
    firmware = set()
    for block in path.read_text(encoding="utf-8").split("----------------------------------------"):
        lines = block.strip().splitlines()
        if not lines or not lines[0].startswith("INF: "):
            continue

        inf_name = Path(lines[0][5:].strip().replace("\\", "/")).name
        if not inf_name.lower().endswith(".inf"):
            continue

        fields = {}
        for line in lines[1:]:
            if ": " in line:
                key, value = line.split(": ", 1)
                if key in {"provider", "hw_ids", "firmware_refs"}:
                    fields[key] = value.strip()

        for hwid in fields.get("hw_ids", "").split(", "):
            if hwid:
                hardware.add((hwid, fields.get("provider", ""), inf_name, "HP-SOFTWARE"))
        for name in fields.get("firmware_refs", "").split(", "):
            if name:
                firmware.add((name, inf_name, "HP-SOFTWARE"))
    return hardware, firmware


def read_rows(path, columns):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        if tuple(reader.fieldnames or ()) != columns:
            raise ValueError(f"Unexpected TSV columns in {path}")
        rows = []
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(row[column] is None for column in columns):
                raise ValueError(f"Malformed TSV row in {path}:{line_number}")
            rows.append(tuple(row[column] for column in columns))
        return rows


def write_rows(path, columns, rows):
    descriptor, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as target:
            writer = csv.writer(target, delimiter="\t", lineterminator="\n")
            writer.writerow(columns)
            writer.writerows(rows)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def promote(manifest, reference_dir, apply):
    hardware, firmware = parse_manifest(manifest)
    if not hardware and not firmware:
        raise ValueError("No INF hardware IDs or firmware references found; no files changed")

    targets = (
        (reference_dir / "hardware-id-candidates.tsv", HARDWARE_COLUMNS, hardware),
        (reference_dir / "firmware-candidates.tsv", FIRMWARE_COLUMNS, firmware),
    )
    changes = []
    for path, columns, incoming in targets:
        existing = read_rows(path, columns)
        additions = sorted(incoming.difference(existing))
        changes.append((path, columns, existing, additions))
        print(f"{path}: {len(additions)} new rows; {len(existing)} existing rows preserved")
        for row in additions:
            print("  ADD " + "\t".join(row))

    if not apply:
        print("Dry run: pass --apply to merge these rows.")
        return

    for path, columns, existing, additions in changes:
        if additions:
            write_rows(path, columns, existing + additions)
    print("Merge complete.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="analysis text from analyze-hp-packages.sh")
    parser.add_argument("--reference-dir", type=Path, default=Path("reference/hp-software"))
    parser.add_argument("--apply", action="store_true", help="merge after reviewing the dry run")
    args = parser.parse_args()
    promote(args.manifest, args.reference_dir, args.apply)


if __name__ == "__main__":
    main()
