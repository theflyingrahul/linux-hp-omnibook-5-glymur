#!/usr/bin/env bash
set -euo pipefail

# Assemble the files that go onto the installer USB's FAT partition for the
# SSD install and boot of the qcom-next Glymur kernel:
#   glymur-tools/ssd/          install-ssd-root.sh, kernel tarball, SHA256SUMS
#   glymur-boot/               vmlinuz-<krel> (fallback copy; GRUB prefers the SSD's)
#   glymur-tools/acpi-override/acpi-override.cpio  (BIOS-gated _OSC fix)
#   glymur-workstation/        fresh repository bundle, SHA256SUMS
#   grub-entry.cfg             entries to append to boot/grub/grub.cfg
#   MANIFEST.sha256            every staged file, for checking the USB copy
#
# Usage (repo root, Git Bash or Linux):
#   scripts/linux/glymur-ssd/make-kit.sh <glymur-kernel-*.tar.gz> <partition-guid> [out-dir]
# The partition GUID and the output are private: keep them in .work/.
# Env: DSDT_FIX_DIR (default .work/dsdt-osc-fix-F.06), DEBS_DIR
# (default .work/ssd-debs: git, git-man, liberror-perl .deb files).

KERNEL_TAR="${1:?usage: make-kit.sh <kernel-tarball> <partition-guid> [out-dir]}"
GUID="$(printf '%s' "${2:?usage: make-kit.sh <kernel-tarball> <partition-guid> [out-dir]}" |
    tr 'A-Z' 'a-z' | tr -d '{}')"
OUT="${3:-.work/ssd-kit}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$REPO/scripts/linux/glymur-ssd"
BOARD="$REPO/boards/hp-omnibook-5-16-bf1xxx"
DSDT_FIX_DIR="${DSDT_FIX_DIR:-$REPO/.work/dsdt-osc-fix-F.06}"
DEBS_DIR="${DEBS_DIR:-$REPO/.work/ssd-debs}"

[[ "$GUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    { echo "not a partition GUID: $GUID" >&2; exit 1; }
KREL="$(tar -tzf "$KERNEL_TAR" | sed -n 's#^\./lib/modules/\([^/]*-glymur\)/$#\1#p' | head -n 1)"
[ -n "$KREL" ] || { echo "no */lib/modules/*-glymur in $KERNEL_TAR" >&2; exit 1; }
BIOS="$(sed -n 's/^bios_version=//p' "$DSDT_FIX_DIR/MANIFEST")"
[ -n "$BIOS" ] && [ -f "$DSDT_FIX_DIR/acpi-override.cpio" ] ||
    { echo "no DSDT override in $DSDT_FIX_DIR" >&2; exit 1; }
BOARD_CMDLINE="$(grep -v '^[[:space:]]*#' "$BOARD/kernel-cmdline.conf" | tr '\n' ' ' |
    sed 's/  */ /g; s/^ //; s/ $//')"

if [ -e "$OUT" ]; then
    echo "refusing to reuse $OUT" >&2
    exit 1
fi
mkdir -p "$OUT/glymur-tools/ssd" "$OUT/glymur-boot" "$OUT/glymur-tools/acpi-override" \
    "$OUT/glymur-workstation"

echo "kernel $KREL, partition $GUID, BIOS gate $BIOS"
cp "$HERE/install-ssd-root.sh" "$HERE/glymur-boot-report.sh" "$KERNEL_TAR" "$OUT/glymur-tools/ssd/"
# git and its two missing dependencies, fetched on an Ubuntu 26.04 arm64
# host with: apt-get download git git-man liberror-perl
if compgen -G "$DEBS_DIR/*.deb" >/dev/null; then
    mkdir -p "$OUT/glymur-tools/ssd/debs"
    cp "$DEBS_DIR"/*.deb "$OUT/glymur-tools/ssd/debs/"
else
    echo "note: no .deb files in $DEBS_DIR; the SSD install will lack git"
fi
(cd "$OUT/glymur-tools/ssd" &&
    sha256sum install-ssd-root.sh glymur-boot-report.sh "$(basename "$KERNEL_TAR")" \
        $(ls debs/*.deb 2>/dev/null) >SHA256SUMS)
# One command for the live session, with this machine's partition filled in.
cat >"$OUT/glymur-setup-ssd.sh" <<EOF
#!/usr/bin/env bash
# Glymur: install Ubuntu onto the internal SSD's Linux partition, then boot
# "Ubuntu on SSD: qcom-next $KREL" from this USB. Run in the RAM live desktop:
#   bash /cdrom/glymur-setup-ssd.sh
# It asks you to type INSTALL, then for a username and password. It never
# touches Windows, Recovery or the SSD's EFI partition.
set -euo pipefail
[ "\$(id -u)" -eq 0 ] || exec sudo bash "\$0" "\$@"
exec bash /cdrom/glymur-tools/ssd/install-ssd-root.sh $GUID "\$@"
EOF
tar -xzf "$KERNEL_TAR" -O ./Image >"$OUT/glymur-boot/vmlinuz-$KREL"
cp "$DSDT_FIX_DIR/acpi-override.cpio" "$OUT/glymur-tools/acpi-override/"
sed -e "s|@KREL@|$KREL|g" -e "s|@PARTUUID@|$GUID|g" -e "s|@BIOS@|$BIOS|g" \
    -e "s|@BOARD_CMDLINE@|$BOARD_CMDLINE|g" -e '/^# Template/d' \
    "$HERE/grub-entry.cfg" >"$OUT/grub-entry.cfg"

# Repository bundle: the working tree with .git and the private .work
# evidence, minus large or regenerable directories.
echo "bundling $REPO"
name="$(basename "$REPO")"
out_abs="$(cd "$OUT" && pwd)"
tar -czf "$out_abs/glymur-workstation/workstation-bundle.tar.gz" \
    --exclude="$name/.work/usb-fat-backup-*" \
    --exclude="$name/.work/pre-pull-backup-*" \
    --exclude="$name/.work/workstation-stage" \
    --exclude="$name/.work/ssd-kit*" \
    --exclude="$name/.work/kernel-*" \
    --exclude='__pycache__' \
    -C "$(dirname "$REPO")" "$name"
(cd "$OUT/glymur-workstation" && sha256sum workstation-bundle.tar.gz >SHA256SUMS)

(cd "$OUT" && find . -type f ! -name MANIFEST.sha256 ! -name grub-entry.cfg | sort |
    sed 's#^\./##' | xargs sha256sum >MANIFEST.sha256)
du -sh "$OUT"
echo "grub entries: $OUT/grub-entry.cfg"
