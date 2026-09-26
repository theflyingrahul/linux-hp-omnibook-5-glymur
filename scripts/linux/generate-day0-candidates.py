#!/usr/bin/env python3
"""Generate scripts/windows/day0-candidates.json from the curated TSVs."""
import csv
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFERENCE_DIR = os.path.join(REPO_ROOT, 'reference', 'hp-software')
OUTPUT_PATH = os.path.join(REPO_ROOT, 'scripts', 'windows', 'day0-candidates.json')


def merge_sources(existing, source):
    # Several INFs can declare the same ID; keep every source rather than
    # silently letting the last TSV row win.
    sources = existing.split('; ') if existing else []
    if source and source not in sources:
        sources.append(source)
    return '; '.join(sources)


def load(name, key_column, value_columns):
    path = os.path.join(REFERENCE_DIR, name)
    candidates = {}
    canonical = {}
    try:
        with open(path, 'r', encoding='utf-8', newline='') as f:
            for row in csv.DictReader(f, delimiter='\t'):
                key = row[key_column]
                # Windows PowerShell 5.1 treats JSON property names as
                # case-insensitive. Collapse case-only variants so the
                # generated object remains consumable there.
                key = canonical.setdefault(key.casefold(), key)
                entry = candidates.setdefault(key, {column: '' for column in value_columns})
                for column in value_columns:
                    if column == 'inf_source':
                        entry[column] = merge_sources(entry[column], row[column])
                    elif not entry[column]:
                        entry[column] = row[column]
    except (OSError, KeyError, csv.Error) as error:
        print(f"ERROR reading {path}: {error}", file=sys.stderr)
        sys.exit(1)
    return candidates


def generate():
    hw_candidates = load('hardware-id-candidates.tsv', 'hardware_id',
                         ('provider', 'inf_source', 'evidence'))
    fw_candidates = load('firmware-candidates.tsv', 'firmware_name',
                         ('inf_source', 'evidence'))

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    # newline='\n' keeps the checked-in file LF on Windows hosts too.
    with open(OUTPUT_PATH, 'w', encoding='utf-8', newline='\n') as f:
        json.dump({
            'hardware_ids': hw_candidates,
            'firmware_names': fw_candidates
        }, f, indent=2, sort_keys=True)
        f.write('\n')


if __name__ == '__main__':
    generate()
