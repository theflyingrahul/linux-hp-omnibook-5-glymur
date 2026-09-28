#!/usr/bin/env bash
set -euo pipefail

# Copy the display-lab kit from the USB to the SSD. A device-tree boot has no
# USB controller enabled, so the lab session cannot read the kit from the USB;
# stage it first from an ACPI boot ("Ubuntu on SSD: newest glymur kernel"),
# where the right USB-A port works:
#
#   bash scripts/linux/glymur-lab/stage-kit.sh [USB-KIT-DIR]
#
# Then boot "Ubuntu on SSD: display lab (device tree)" and run
#   sudo bash ~/glymur-lab-kit/start-lab.sh

SRC="${1:-$(ls -d /media/"$USER"/*/glymur-tools/lab 2>/dev/null | head -n1)}"
DST="$HOME/glymur-lab-kit"

[ -n "$SRC" ] && [ -f "$SRC/SHA256SUMS" ] || { echo 'lab kit not found on the USB; pass its path' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }
(cd "$SRC" && sha256sum --quiet -c SHA256SUMS) || { echo 'kit checksum mismatch; refusing' >&2; exit 1; }
rm -rf "$DST"
cp -a "$SRC" "$DST"
(cd "$DST" && sha256sum --quiet -c SHA256SUMS)
echo "Kit staged and verified at $DST."
