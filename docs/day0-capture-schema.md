# Day-0 Capture Schema

Schema Version: 1

## Directory Layout
- `public/`: Normalized, generally safe TSV/JSON (PnP, System info). Still requires review.
- `raw/`: Verbose Windows tool outputs (e.g., `pnputil`, registry exports, ACPI binaries).
- `private/`: Proprietary firmware, full driver exports, and unique identity data.
- `logs/`: PowerShell execution logs and errors.

## `capture.json`
Contains metadata about the run:
- `schema_version`
- `script_version`
- `capture_start` / `capture_end`
- `elevated` boolean
- `section_statuses` (PASS/FAIL/SKIPPED/PARTIAL)
- `enabled_switches`

## Hash Manifest
`SHA256SUMS.tsv` is generated at the end of capture, covering all files (except itself) in the output directory.
