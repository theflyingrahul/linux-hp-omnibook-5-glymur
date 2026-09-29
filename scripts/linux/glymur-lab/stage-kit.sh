#!/usr/bin/env bash
set -euo pipefail

# Copy the display-lab kit from the USB to the SSD. A device-tree boot has no
# USB controller enabled, so the lab session cannot read the kit from the USB;
# stage it first from an ACPI boot ("Ubuntu on SSD: ACPI, newest glymur kernel"),
# where the right USB-A port works:
#
#   bash scripts/linux/glymur-lab/stage-kit.sh [USB-KIT-DIR]
#
# Then boot the display-lab entry and run
#   sudo bash ~/glymur-lab-kit/start-lab.sh
#
# The display-lab GRUB entry was taken off the USB menu on 2026-09-29 (its
# display phase hung the laptop twice); restore it from
# scripts/linux/glymur-ssd/grub-entry.cfg at commit 1f18e2f to run the lab.

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
