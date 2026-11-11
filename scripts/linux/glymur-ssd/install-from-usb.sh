#!/usr/bin/env bash
set -euo pipefail

# Install everything staged on the USB. See README.md.
#   bash install-from-usb.sh [--keep-ubuntu-mesa] [kernel release]
# Default kernel: 7.3.0-glymur-21.

SYSTEM_MESA=1
if [ "${1:-}" = --keep-ubuntu-mesa ]; then SYSTEM_MESA=0; shift; fi
KREL="${1:-7.3.0-glymur-21}"
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

# HP's CDSP-side FastRPC files (NPU driver qcnspmcdm8480), from -20.
if [ -d "$K/npu/cdsp" ]; then
    echo "== installing HP's CDSP FastRPC files"
    D=/usr/share/qcom/glymur/HP/omnibook-5-16-bf1xxx/dsp/cdsp
    sudo install -d "$D"
    sudo install -m 644 "$K/npu/cdsp/"* "$D/"
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

# EFI variables: read-only from -17, read-write from -20 (the owner allowed
# writes on 2026-11-09; docs/kernel-20-plan-2026-11-09.md). The EFI pstore
# backend stays off in the kernel, and grub-install and fwupd stay disabled.
EFI_LINE='efivarfs /sys/firmware/efi/efivars efivarfs rw,nosuid,nodev,noexec 0 0'
if ! grep -qxF "$EFI_LINE" /etc/fstab; then
    echo "== mounting efivarfs read-write from the next boot on"
    sudo cp -n /etc/fstab /etc/fstab.before-glymur-20
    sudo sed -i '/^efivarfs /d' /etc/fstab
    echo "$EFI_LINE" | sudo tee -a /etc/fstab
fi

# s2idle only (from -21): on -20 every "deep" attempt failed in the firmware
# (PSCI system suspend, -95) before falling back, and one hung. systemd's
# MemorySleepMode keeps it from trying; the kernel command line is unchanged.
SLEEP_CONF=/etc/systemd/sleep.conf.d/glymur-s2idle.conf
if [ ! -f "$SLEEP_CONF" ]; then
    echo "== suspend: s2idle only"
    sudo install -d "$(dirname "$SLEEP_CONF")"
    printf '[Sleep]\nMemorySleepMode=s2idle\n' | sudo tee "$SLEEP_CONF" >/dev/null
fi

if [ -d "$K/boot-logo" ]; then
    echo "== the firmware's boot logo for plymouth"
    sudo bash "$K/install-boot-logo.sh"
fi

if [ -d "$K/audio" ]; then
    echo "== installing the audio topology and UCM profile"
    sudo bash "$K/install-audio.sh"
fi

# GNOME shows the backlight level itself; the timeout (hold F5) needs this
# extension. A new extension loads at the next login on Wayland.
EXT=kbd-backlight-timeout-osd@hp-omnibook-5
if [ -d "$K/gnome-shell/$EXT" ]; then
    echo "== GNOME extension: the keyboard backlight timeout OSD"
    D="$HOME/.local/share/gnome-shell/extensions/$EXT"
    mkdir -p "$D"
    cp "$K/gnome-shell/$EXT/"* "$D/"
    cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)
    case "$cur" in
        *"'$EXT'"*) ;;
        "@as []"|"[]"|"") gsettings set org.gnome.shell enabled-extensions "['$EXT']" ;;
        *) gsettings set org.gnome.shell enabled-extensions "${cur%]}, '$EXT']" ;;
    esac
    echo "enabled from the next login: $(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)"
fi

echo "== test tools from Ubuntu (glxinfo/eglinfo, vulkaninfo/vkcube, glmark2, kmscube)"
sudo apt-get install -y mesa-utils mesa-utils-bin vulkan-tools glmark2-es2-wayland kmscube ||
    echo 'apt failed (offline?); install them later, check-mesa.sh names them'

for f in check-gpu-test.sh check-mesa.sh charging-watch.sh check-usb.sh check-ec.sh gpu-corruption-test.sh \
         check-audio.sh check-headset.sh watch-audio.sh check-battmgr-notify.sh check-video.sh \
         check-display.sh check-hotkeys.sh ec-event-capture.sh dump-efivars.sh          check-suspend.sh check-rtc.sh check-efivars-write.sh check-npu.sh setup-npu.sh npu-caps.c \
         check-chid.sh stubble-hwids.py; do
    if [ -f "$K/$f" ]; then cp "$K/$f" "$HOME/$f"; fi
done
# The WirePlumber rule for a boot with Iris on: kept aside, never installed.
if [ -d "$K/iris-test" ]; then
    mkdir -p "$HOME/glymur-iris-test"
    cp "$K/iris-test/"*.conf "$HOME/glymur-iris-test/"
fi
sync
echo
echo "Done. Reboot into \"Ubuntu on SSD: test device tree\" and follow"
echo "docs/linux-runbook-21-2026-11-10.md. The checks, from a terminal:"
echo "  sudo bash ~/check-chid.sh       (hardware IDs for systemd-stub/stubble; no external monitor)"
echo "  sudo bash ~/check-efivars-write.sh   (one EFI variable write; --verify after the reboot)"
echo "  sudo bash ~/check-rtc.sh        (RTC time, UTC or local, one alarm)"
echo "  sudo bash ~/check-npu.sh        (NPU: FastRPC on the CDSP)"
echo "  sudo bash ~/check-suspend.sh    (last: three supervised suspend cycles)"
echo "  bash ~/check-mesa.sh"
echo "  sudo bash ~/check-headset.sh    (headset jack; have a wired headset at hand)"
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
