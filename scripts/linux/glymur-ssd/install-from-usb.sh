#!/usr/bin/env bash
set -euo pipefail

# One command for any boot that can see the USB stick (an ACPI boot, or
# "device tree (GPU and USB-A test)" once its USB-A port works), run from
# the USB's glymur-tools/kernels directory as your normal user (it asks for
# your password through sudo):
#
#   bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"
#
# It checks every file against SHA256SUMS, then installs what is staged and
# not yet installed: the kernel package, the Adreno GPU firmware, the Mesa
# build (under /opt/mesa-glymur, beside Ubuntu's), and the boot service
# that loads scmi-cpufreq on the GPU test device tree. The check scripts
# are copied to your home directory, because device-tree boots cannot see
# the USB. Default kernel: 7.3.0-rc2-glymur-5; pass another release as the
# first argument.

KREL="${1:-7.3.0-rc2-glymur-5}"
K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -ne 0 ] || { echo 'run as your normal user, not with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo 'not booted from the SSD install (glymur-root); refusing' >&2; exit 1; }

echo "== checking the files on the USB"
(cd "$K" && sha256sum --quiet -c SHA256SUMS) || { echo 'checksum mismatch; nothing installed' >&2; exit 1; }
echo 'all files OK'

if [ "$(readlink /boot/vmlinuz-glymur 2>/dev/null)" = "vmlinuz-$KREL" ]; then
    echo "== kernel $KREL is already the newest; skipped"
else
    [ -f "$K/glymur-kernel-$KREL.tar.gz" ] || { echo "no glymur-kernel-$KREL.tar.gz in $K" >&2; exit 1; }
    echo "== installing kernel $KREL"
    sudo bash "$K/install-kernel.sh" "$K/glymur-kernel-$KREL.tar.gz"
fi

echo "== installing the GPU firmware"
sudo bash "$K/install-gpu-firmware.sh" "$K/gpu-fw"

MESA="$(ls "$K"/mesa-glymur-*.tar.gz 2>/dev/null | sort -V | tail -1)"
if [ -n "$MESA" ]; then
    echo "== installing $(basename "$MESA")"
    sudo bash "$K/install-mesa.sh" "$MESA"
fi

if [ -f "$K/glymur-cpufreq.service" ]; then
    echo "== installing the cpufreq boot service"
    sudo bash "$K/install-cpufreq-service.sh"
fi

echo "== test tools from Ubuntu (glxinfo/eglinfo, vulkaninfo/vkcube, glmark2)"
sudo apt-get install -y mesa-utils mesa-utils-bin vulkan-tools glmark2-es2-wayland ||
    echo 'apt failed (offline?); install them later, check-mesa.sh names them'

for f in check-gpu-test.sh check-mesa.sh charging-watch.sh check-usb.sh; do
    if [ -f "$K/$f" ]; then cp "$K/$f" "$HOME/$f"; fi
done
sync
echo
echo "Done. Reboot into \"Ubuntu on SSD: device tree (GPU and USB-A test)\""
echo "(or \"GPU test\" if the USB-A port does not come up) and, from a terminal"
echo "on the desktop, run:"
echo "  bash ~/check-mesa.sh"
echo "and, with the charger at hand (type notes as you plug and unplug):"
echo "  sudo bash ~/charging-watch.sh"
