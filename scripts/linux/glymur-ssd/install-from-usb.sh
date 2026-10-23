#!/usr/bin/env bash
set -euo pipefail

# Install everything staged on the USB. See README.md.
#   bash install-from-usb.sh [--keep-ubuntu-mesa] [kernel release]
# Default kernel: 7.3.0-rc4-glymur-17.

SYSTEM_MESA=1
if [ "${1:-}" = --keep-ubuntu-mesa ]; then SYSTEM_MESA=0; shift; fi
KREL="${1:-7.3.0-rc4-glymur-17}"
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

# HP's video firmware (Iris), from the Windows display driver package.
if [ -f "$K/hp-fw/qcvss8480.mbn" ]; then
    echo "== installing HP's video firmware"
    sudo install -D -m 644 "$K/hp-fw/qcvss8480.mbn" \
        /usr/lib/firmware/updates/qcom/glymur/HP/omnibook-5-16-bf1xxx/qcvss8480.mbn
fi

MESA="$(ls "$K"/mesa-glymur-*.tar.gz 2>/dev/null | sort -V | tail -1)"
if [ -n "$MESA" ]; then
    echo "== installing $(basename "$MESA")"
    sudo bash "$K/install-mesa.sh" "$MESA"
    if [ "$SYSTEM_MESA" = 1 ]; then
        echo "== switching the system to it"
        sudo mesa-glymur-run --system on
        mesa-glymur-run --desktop off >/dev/null 2>&1 || true
    fi
fi

if [ -f "$K/glymur-cpufreq.service" ]; then
    echo "== installing the cpufreq boot service"
    sudo bash "$K/install-cpufreq-service.sh"
fi

# lscpu with the Oryon-2 part ID (util-linux PR #4657), beside Ubuntu's.
if [ -f "$K/lscpu-oryon2.tar.gz" ]; then
    echo "== installing lscpu with the Oryon-2 part ID into /usr/local"
    L=/usr/local/lib/glymur-lscpu
    sudo rm -rf "$L"
    sudo mkdir -p "$L"
    sudo tar -xzf "$K/lscpu-oryon2.tar.gz" -C "$L" --strip-components=1 lib/
    sudo tar -xzf "$K/lscpu-oryon2.tar.gz" -C /usr/local/bin lscpu
    echo "as user: $(lscpu | grep 'Model name')"
    echo "as root: $(sudo lscpu | grep 'Model name' | head -1)"
fi

# EFI variables (from -17): read-only until writes are allowed on purpose.
# Remount read-write by hand for a single write (docs/uefi-variables-2026-10-23.md).
if ! grep -q '^efivarfs ' /etc/fstab; then
    echo "== mounting efivarfs read-only from the next boot on"
    echo 'efivarfs /sys/firmware/efi/efivars efivarfs ro,nosuid,nodev,noexec 0 0' | sudo tee -a /etc/fstab
fi

if [ -d "$K/boot-logo" ]; then
    echo "== the firmware's boot logo for plymouth"
    sudo bash "$K/install-boot-logo.sh"
fi

if [ -d "$K/audio" ]; then
    echo "== installing the audio topology and UCM profile"
    sudo bash "$K/install-audio.sh"
fi

echo "== test tools from Ubuntu (glxinfo/eglinfo, vulkaninfo/vkcube, glmark2, kmscube)"
sudo apt-get install -y mesa-utils mesa-utils-bin vulkan-tools glmark2-es2-wayland kmscube ||
    echo 'apt failed (offline?); install them later, check-mesa.sh names them'

for f in check-gpu-test.sh check-mesa.sh charging-watch.sh check-usb.sh check-ec.sh gpu-corruption-test.sh \
         check-audio.sh watch-audio.sh check-battmgr-notify.sh check-video.sh check-display.sh \
         check-hotkeys.sh ec-event-capture.sh dump-efivars.sh; do
    if [ -f "$K/$f" ]; then cp "$K/$f" "$HOME/$f"; fi
done
sync
echo
echo "Done. Reboot into \"Ubuntu on SSD: test device tree\" and,"
echo "from a terminal on the desktop, run:"
echo "  bash ~/check-mesa.sh"
echo "  sudo bash ~/check-ec.sh         (fan, temperatures, backlight, mute LEDs, hotkeys)"
echo "  sudo bash ~/check-usb.sh        (plug USB-C and USB 2.0 devices in first)"
echo "  sudo bash ~/charging-watch.sh   (plug, unplug, replug; type notes)"
echo "  sudo bash ~/check-audio.sh      (speakers, microphones, names, mute LEDs, F6/F9)"
echo "  sudo bash ~/watch-audio.sh      (leave running: what drops the speaker amplifiers)"
echo "  sudo bash ~/check-battmgr-notify.sh   (with the charger at hand)"
echo "  sudo bash ~/check-video.sh      (hardware video decoding)"
echo "  sudo bash ~/check-display.sh    (external monitor on each USB-C port)"
echo "If the desktop is still corrupted, press Ctrl+Alt+F3, log in, and run"
echo "  bash ~/gpu-corruption-test.sh"
if [ "$SYSTEM_MESA" = 1 ] && [ -n "$MESA" ]; then
    echo "If the desktop does not come up, press Ctrl+Alt+F3, log in, and run"
    echo "  sudo mesa-glymur-run --system off && sudo reboot"
fi
