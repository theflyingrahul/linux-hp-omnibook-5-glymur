#!/usr/bin/env bash
set -euo pipefail

# Install a glymur kernel build and make it the newest. See README.md.
#   sudo bash install-kernel.sh <glymur-kernel-*.tar.gz | build-output-dir>

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
if [ -d "$stage/dtbs" ]; then
    rm -rf "$BOOT/dtbs/$krel"
    mkdir -p "$BOOT/dtbs/$krel"
    cp -a "$stage/dtbs/." "$BOOT/dtbs/$krel/"
fi

running="$(uname -r)"
[ -f "$BOOT/vmlinuz-$running" ] && ln -sfn "vmlinuz-$running" "$BOOT/vmlinuz-glymur.old"
ln -sfn "vmlinuz-$krel" "$BOOT/vmlinuz-glymur"
if [ -d "$BOOT/dtbs/$krel/qcom" ]; then
    [ -d "$BOOT/dtbs/$running/qcom" ] && ln -sfn "dtbs/$running/qcom" "$BOOT/glymur-dtb.old"
    ln -sfn "dtbs/$krel/qcom" "$BOOT/glymur-dtb"
fi

report="$(dirname "${BASH_SOURCE[0]}")/glymur-boot-report.sh"
if [ -f "$report" ] && [ -f /etc/systemd/system/glymur-boot-report.service ]; then
    install -m 755 "$report" /usr/local/sbin/glymur-boot-report
    echo 'Updated /usr/local/sbin/glymur-boot-report.'
fi
sync
ls -l "$BOOT"/vmlinuz-glymur "$BOOT"/vmlinuz-glymur.old "$BOOT"/glymur-dtb "$BOOT"/glymur-dtb.old 2>/dev/null
ls -l "$BOOT/glymur-dtb/" 2>/dev/null
echo "Reboot and choose \"Ubuntu on SSD\" to boot $krel."
