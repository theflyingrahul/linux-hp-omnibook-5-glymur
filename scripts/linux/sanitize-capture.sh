#!/usr/bin/env bash
set -euo pipefail

# Replace personal identifiers in text captures before they are committed:
# MAC and Bluetooth addresses, UUIDs (partition, filesystem, PARTUUID=),
# USB serial numbers, and the Windows volume labels lsblk prints. Edits the
# files in place, then lists any line that still looks like an identifier
# so it can be checked by hand. See captures/README.md.
#   scripts/linux/sanitize-capture.sh <file>...

[ $# -gt 0 ] || { echo "usage: $0 <file>..." >&2; exit 1; }
for f in "$@"; do
    grep -Iq . "$f" 2>/dev/null || { echo "skipped (binary or empty): $f"; continue; }
    sed -E -i \
        -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
        -e 's/\b[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b/<uuid>/g' \
        -e 's/(SerialNumber: ).*/\1<serial>/' \
        -e 's/(iSerial +[0-9]+ ).*/\1<serial>/' \
        -e 's/(BitLocker +)[^ ]+/\1<label>/' \
        -e 's/([^ ]+)( +Windows +[0-9]+\/[0-9]+\/[0-9]+ +BitLocker)/<label>\2/' \
        "$f"
done
# Anything left that looks like an identifier, for a manual check.
grep -n -I -i -E 'serial|uuid|[0-9a-f]{2}(-[0-9a-f]{2}){5}|ssid|inet6? [0-9]' "$@" 2>/dev/null |
    grep -v -E '<uuid>|<serial>|SerialNumber=[0-9]|serial(8250|_|-engine| bus)|\.serial|msm_serial|SerialBus|serial device' | head -20 || true
