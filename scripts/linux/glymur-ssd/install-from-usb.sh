#!/usr/bin/env bash
set -euo pipefail

# One command for any boot that can see the USB stick (an ACPI boot, or
# "device tree (GPU and USB-A test)", whose USB-A port works), run from
# the USB's glymur-tools/kernels directory as your normal user (it asks for
# your password through sudo):
#
#   bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"
#
# It checks every file against SHA256SUMS, then installs what is staged:
# - the kernel package (skipped if it is already the newest), with its
#   device trees;
# - the Adreno GPU firmware;
# - the newest Mesa build under /opt/mesa-glymur, and switches the whole
#   system to it (sudo mesa-glymur-run --system on; undo with --system
#   off). Pass --keep-ubuntu-mesa to install it without switching;
# - the boot service that loads scmi-cpufreq where the device tree allows;
# - the test tools from Ubuntu, and the check scripts into your home
#   directory.
#
#   install-from-usb.sh [--keep-ubuntu-mesa] [kernel release]
# Default kernel: 7.3.0-rc2-glymur-6.

SYSTEM_MESA=1
if [ "${1:-}" = --keep-ubuntu-mesa ]; then SYSTEM_MESA=0; shift; fi
KREL="${1:-7.3.0-rc2-glymur-6}"
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
    if [ "$SYSTEM_MESA" = 1 ]; then
        echo "== switching the system to it"
        sudo mesa-glymur-run --system on
        # The older per-user switch is superseded; remove it if present.
        mesa-glymur-run --desktop off >/dev/null 2>&1 || true
    fi
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
echo "Done. Reboot into \"Ubuntu on SSD: device tree (GPU and USB-A test)\" and,"
echo "from a terminal on the desktop, run:"
echo "  bash ~/check-mesa.sh"
echo "  sudo bash ~/check-usb.sh        (plug USB-C and USB 2.0 devices in first)"
echo "  sudo bash ~/charging-watch.sh   (plug, unplug, replug; type notes)"
if [ "$SYSTEM_MESA" = 1 ] && [ -n "$MESA" ]; then
    echo "If the desktop does not come up, press Ctrl+Alt+F3, log in, and run"
    echo "  sudo mesa-glymur-run --system off && sudo reboot"
fi
