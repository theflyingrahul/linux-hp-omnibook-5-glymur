#!/usr/bin/env bash
set -euo pipefail

# Build the ACPI input test modules for the installer's stock Ubuntu kernel.
# Usage: build.sh <ubuntu-7.0-source-tree> [kernel-release] [output-dir]
# The GENI I2C driver is derived from that tree's i2c-qcom-geni.c, whose
# SHA-256 must match Linux v7.0 (checked by derive-geni-i2c.py).

SRC_TREE="${1:?usage: build.sh <ubuntu-source-tree> [kernel-release] [output-dir]}"
KREL="${2:-7.0.0-30-generic}"
OUT="${3:-.work/glymur-acpi-input}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDIR="/usr/src/linux-headers-$KREL"

if [ ! -d "$KDIR" ]; then
    printf 'Missing kernel headers: %s\n' "$KDIR" >&2
    exit 1
fi

mkdir -p "$OUT"
OUT="$(realpath "$OUT")"
cp "$HERE/Makefile" "$HERE/glymur_acpi_gpio.c" "$OUT/"
python3 "$HERE/derive-geni-i2c.py" \
    "$SRC_TREE/drivers/i2c/busses/i2c-qcom-geni.c" "$OUT/glymur_geni_i2c.c"

make -C "$KDIR" M="$OUT" modules
if [ -x "$SRC_TREE/scripts/checkpatch.pl" ]; then
    "$SRC_TREE/scripts/checkpatch.pl" --no-tree --terse -f "$OUT/glymur_acpi_gpio.c" || true
fi

for module in glymur_acpi_gpio glymur_geni_i2c; do
    modinfo -F vermagic "$OUT/$module.ko"
done
sha256sum "$OUT"/*.ko "$OUT/glymur_geni_i2c.c" | tee "$OUT/SHA256SUMS"
