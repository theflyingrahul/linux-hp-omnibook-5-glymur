#!/usr/bin/env bash
set -euo pipefail

# One command for an ACPI boot ("Ubuntu on SSD: ACPI, newest glymur kernel"),
# run from the USB's glymur-tools/kernels directory as your normal user
# (it asks for your password through sudo):
#
#   bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"
#
# It checks every file against SHA256SUMS, installs the kernel package and
# the Adreno GPU firmware, and copies check-gpu-test.sh to your home
# directory (device-tree boots cannot see the USB). Default kernel:
# 7.3.0-rc2-glymur-5; pass another release as the first argument.

KREL="${1:-7.3.0-rc2-glymur-5}"
K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -ne 0 ] || { echo 'run as your normal user, not with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo 'not booted from the SSD install (glymur-root); refusing' >&2; exit 1; }
[ -f "$K/glymur-kernel-$KREL.tar.gz" ] || { echo "no glymur-kernel-$KREL.tar.gz in $K" >&2; exit 1; }

echo "== checking the files on the USB"
(cd "$K" && sha256sum --quiet -c SHA256SUMS) || { echo 'checksum mismatch; nothing installed' >&2; exit 1; }
echo 'all files OK'

echo "== installing kernel $KREL"
sudo bash "$K/install-kernel.sh" "$K/glymur-kernel-$KREL.tar.gz"

echo "== installing the GPU firmware"
sudo bash "$K/install-gpu-firmware.sh" "$K/gpu-fw"

cp "$K/check-gpu-test.sh" "$HOME/check-gpu-test.sh"
sync
echo
echo "Done. Reboot into \"Ubuntu on SSD: device tree (GPU test)\" and run:"
echo "  sudo bash ~/check-gpu-test.sh --charging"
echo "then, with nothing unsaved:"
echo "  sudo bash ~/check-gpu-test.sh --cpufreq"
