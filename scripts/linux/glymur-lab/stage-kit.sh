#!/usr/bin/env bash
set -euo pipefail

# Copy the display-lab kit from the USB to the SSD (from an ACPI boot). See README.md.
#   bash scripts/linux/glymur-lab/stage-kit.sh [USB-KIT-DIR]

# The desktop mounts the USB under /run/media/$USER (udisks) or /media/$USER.
SRC="${1:-}"
if [ -z "$SRC" ]; then
    for d in /run/media/"$USER"/*/glymur-tools/lab /media/"$USER"/*/glymur-tools/lab; do
        [ -f "$d/SHA256SUMS" ] && { SRC="$d"; break; }
    done
fi
DST="$HOME/glymur-lab-kit"

[ -n "$SRC" ] && [ -f "$SRC/SHA256SUMS" ] || { echo 'lab kit not found on the USB; pass its path' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }
(cd "$SRC" && sha256sum --quiet -c SHA256SUMS) || { echo 'kit checksum mismatch; refusing' >&2; exit 1; }
rm -rf "$DST"
cp -a "$SRC" "$DST"
(cd "$DST" && sha256sum --quiet -c SHA256SUMS)
echo "Kit staged and verified at $DST."
