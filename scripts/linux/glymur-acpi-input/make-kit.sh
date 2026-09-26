#!/usr/bin/env bash
set -euo pipefail

# Assemble the installer-USB kit: modules, counter, and a collector with the
# module hashes pinned.
# Usage: make-kit.sh <module-build-dir> <kit-output-dir> [private-board-2.bin]
# The optional board-2.bin (from ../ath12k-board-add.py) enables the Wi-Fi
# stage; it contains Windows-derived board data and must stay out of Git.
# If GSI_BUILD names a directory with glymur_gpi_dma.ko and
# glymur_geni_i2c_gsi.ko (derive-gpi-dma.py, derive-geni-i2c.py --gsi), the
# desktop setup also binds the EC bus.
# Copy <kit-output-dir> to <installer>/glymur-tools/acpi-input/ and append
# grub-entry.cfg to the installer's boot/grub/grub.cfg (after backing it up).

BUILD="${1:?usage: make-kit.sh <module-build-dir> <kit-output-dir> [board-2.bin]}"
KIT="${2:?usage: make-kit.sh <module-build-dir> <kit-output-dir> [board-2.bin]}"
BOARD="${3:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hash_of() { sha256sum "$1" | cut -d ' ' -f 1; }

rm -rf "$KIT"
mkdir -p "$KIT"
cp "$BUILD/glymur_acpi_gpio.ko" "$BUILD/glymur_geni_i2c.ko" "$KIT/"
cp "$HERE/glymur-input-counter.py" "$KIT/"

GPI_HASH=none
GSI_HASH=none
if [ -n "${GSI_BUILD:-}" ]; then
    cp "$GSI_BUILD/glymur_gpi_dma.ko" "$GSI_BUILD/glymur_geni_i2c_gsi.ko" "$KIT/"
    GPI_HASH="$(hash_of "$KIT/glymur_gpi_dma.ko")"
    GSI_HASH="$(hash_of "$KIT/glymur_geni_i2c_gsi.ko")"
fi

WIFI_HASH=none
if [ -n "$BOARD" ]; then
    mkdir -p "$KIT/wifi"
    cp "$BOARD" "$KIT/wifi/board-2.bin"
    WIFI_HASH="$(hash_of "$KIT/wifi/board-2.bin")"
fi

for script in glymur-acpi-input-test.sh glymur-live-desktop-setup.sh; do
    sed -e "s/@GPIO_SHA256@/$(hash_of "$KIT/glymur_acpi_gpio.ko")/" \
        -e "s/@I2C_SHA256@/$(hash_of "$KIT/glymur_geni_i2c.ko")/" \
        -e "s/@COUNTER_SHA256@/$(hash_of "$KIT/glymur-input-counter.py")/" \
        -e "s/@WIFI_BOARD_SHA256@/$WIFI_HASH/" \
        -e "s/@GPI_SHA256@/$GPI_HASH/" \
        -e "s/@GSI_SHA256@/$GSI_HASH/" \
        "$HERE/$script" >"$KIT/$script"
    chmod 755 "$KIT/$script"
    if grep -q '@[A-Z0-9_]*_SHA256@' "$KIT/$script"; then
        printf 'Unsubstituted hash placeholder in %s\n' "$script" >&2
        exit 1
    fi
    bash -n "$KIT/$script"
done
cp "$HERE/grub-entry.cfg" "$HERE/desktop-grub-entry.cfg" "$HERE/workstation-grub-entry.cfg" "$KIT/"
(cd "$KIT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort |
    xargs sha256sum -- >SHA256SUMS)
cat "$KIT/SHA256SUMS"
