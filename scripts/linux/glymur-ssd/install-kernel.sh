#!/usr/bin/env bash
set -euo pipefail

# Install a glymur kernel build on the SSD root and make it the one the USB's
# "Ubuntu on SSD: newest glymur kernel" entry boots, keeping the previous one
# for the "previous glymur kernel" entry. Nothing on the USB or the SSD's EFI
# partition changes: GRUB follows these symlinks in /boot.
#
#   sudo bash install-kernel.sh <glymur-kernel-*.tar.gz | build-output-dir>
#
# The input is the tarball from build-qcom-next-glymur.sh, or its output
# directory (which has stage/Image and stage/lib/modules/<krel>). Build with
# GLYMUR_SUFFIX=-N so each build has its own release; installing the
# release that is running now is refused, because it would replace the
# modules of the live kernel.

SRC="${1:?usage: install-kernel.sh <kernel tarball | build output dir>}"
BOOT=/boot
MODS=/usr/lib/modules

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ "$(findmnt -n -o LABEL /)" = glymur-root ] || { echo '/ is not glymur-root; refusing' >&2; exit 1; }

work="$(mktemp -d /var/tmp/glymur-kernel.XXXXXX)"
trap 'rm -rf "$work"' EXIT
if [ -f "$SRC" ]; then
    tar -xzf "$SRC" -C "$work"
    stage="$work"
elif [ -d "$SRC/stage" ]; then
    stage="$SRC/stage"
else
    echo "$SRC is neither a kernel tarball nor a build output directory" >&2
    exit 1
fi
krel="$(ls "$stage/lib/modules" | grep -- '-glymur' | head -n 1 || true)"
[ -n "$krel" ] && [ -f "$stage/Image" ] || { echo 'no Image or glymur modules found' >&2; exit 1; }
if [ "$krel" = "$(uname -r)" ]; then
    echo "$krel is the running kernel; rebuild with GLYMUR_SUFFIX=-N" >&2
    exit 1
fi

echo "Installing $krel"
rm -rf "${MODS:?}/$krel"
cp -a "$stage/lib/modules/$krel" "$MODS/"
rm -f "$MODS/$krel/build" "$MODS/$krel/source"
install -m 644 "$stage/Image" "$BOOT/vmlinuz-$krel"
[ -f "$stage/.config" ] && install -m 644 "$stage/.config" "$BOOT/config-$krel"
[ -f "$stage/System.map" ] && install -m 644 "$stage/System.map" "$BOOT/System.map-$krel"
depmod -a "$krel"
# Device trees built with this kernel (the USB's device-tree entries load
# them through /boot/glymur-dtb).
if [ -d "$stage/dtbs" ]; then
    rm -rf "$BOOT/dtbs/$krel"
    mkdir -p "$BOOT/dtbs/$krel"
    cp -a "$stage/dtbs/." "$BOOT/dtbs/$krel/"
fi

# Rotate: the kernel that is running now becomes "previous".
running="$(uname -r)"
[ -f "$BOOT/vmlinuz-$running" ] && ln -sfn "vmlinuz-$running" "$BOOT/vmlinuz-glymur.old"
ln -sfn "vmlinuz-$krel" "$BOOT/vmlinuz-glymur"
if [ -d "$BOOT/dtbs/$krel/qcom" ]; then
    [ -d "$BOOT/dtbs/$running/qcom" ] && ln -sfn "dtbs/$running/qcom" "$BOOT/glymur-dtb.old"
    ln -sfn "dtbs/$krel/qcom" "$BOOT/glymur-dtb"
fi

# The per-boot report evolves with the kernels (device-tree sections), so
# refresh it from this checkout too.
report="$(dirname "${BASH_SOURCE[0]}")/glymur-boot-report.sh"
if [ -f "$report" ] && [ -f /etc/systemd/system/glymur-boot-report.service ]; then
    install -m 755 "$report" /usr/local/sbin/glymur-boot-report
    echo 'Updated /usr/local/sbin/glymur-boot-report.'
fi
sync
ls -l "$BOOT"/vmlinuz-glymur "$BOOT"/vmlinuz-glymur.old "$BOOT"/glymur-dtb "$BOOT"/glymur-dtb.old 2>/dev/null
ls -l "$BOOT/glymur-dtb/" 2>/dev/null
echo "Reboot and choose \"Ubuntu on SSD: newest glymur kernel\" (ACPI) or"
echo "\"Ubuntu on SSD: device tree (full)\" to boot $krel."
