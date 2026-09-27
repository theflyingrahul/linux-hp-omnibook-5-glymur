#!/usr/bin/env bash
set -euo pipefail

# Build Qualcomm's qcom-next kernel with the Glymur ACPI patches for booting
# the HP OmniBook 5 from the internal-SSD Ubuntu root (no initramfs; the only
# initrd is the early ACPI-table cpio). Run from ~/glymur-build in WSL.
#
# Config: Ubuntu's config-7.0.0-30-generic + arch/arm64/configs/qcom.config +
# glymur.config below (the combination chosen in the Linux live session).
# NVMe, ext4 and the PCI/ACPI host path are built in so the kernel can mount
# root=PARTUUID=... directly.

SRC="${1:-.work/linux-qcom-next-glymur}"
OUT="${2:-.work/build/qcom-next-glymur}"
JOBS="${3:-8}"
UBUNTU_CONFIG="${UBUNTU_CONFIG:-/usr/src/linux-headers-7.0.0-30-generic/.config}"
# GLYMUR_SUFFIX (for example -2) gives each build its own release,
# 7.3.0-rc2-glymur-2, so installing it never replaces the running kernel's
# modules (see glymur-ssd/install-kernel.sh). Works in WSL and natively on
# the SSD install, which also has Ubuntu's 7.0 headers.
SUFFIX="${GLYMUR_SUFFIX:-}"
case "$SUFFIX" in
    '' | -[A-Za-z0-9]*) ;;
    *) printf 'GLYMUR_SUFFIX must start with - (got %s)\n' "$SUFFIX" >&2; exit 2 ;;
esac

SRC="$(realpath "$SRC")"
mkdir -p "$OUT"
OUT="$(realpath "$OUT")"
# An empty LOCALVERSION stops setlocalversion appending "+" for an untagged
# tree, so the release is exactly <version>-glymur.
MAKE=(make -C "$SRC" "O=$OUT" ARCH=arm64 "-j$JOBS" "LOCALVERSION=$SUFFIX")

cat >"$OUT/glymur.config" <<'CFG'
CONFIG_LOCALVERSION="-glymur"
# CONFIG_LOCALVERSION_AUTO is not set
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_DEBUG_INFO_DWARF5 is not set
# CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT is not set
# CONFIG_DEBUG_INFO_BTF is not set
CONFIG_SYSTEM_TRUSTED_KEYS=""
CONFIG_SYSTEM_REVOCATION_KEYS=""
# CONFIG_MODULE_SIG is not set
# CONFIG_MODULE_SIG_FORCE is not set
CONFIG_NVME_CORE=y
CONFIG_BLK_DEV_NVME=y
CONFIG_EXT4_FS=y
CONFIG_ACPI_TABLE_UPGRADE=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_GPIO_GLYMUR_ACPI=m
CONFIG_QCOM_GPI_DMA=m
CONFIG_I2C_QCOM_GENI=m
CONFIG_I2C_HID_ACPI=m
CONFIG_HID_MULTITOUCH=m
# Device-tree boot without an initramfs: everything between the kernel and
# the NVMe root is built in (clock, pin and interconnect controllers, TCSR
# reference clocks, the QMP PCIe PHY). All are inert on an ACPI boot.
CONFIG_CLK_GLYMUR_GCC=y
CONFIG_CLK_GLYMUR_TCSRCC=y
CONFIG_PINCTRL_GLYMUR=y
CONFIG_INTERCONNECT_QCOM_GLYMUR=y
CONFIG_PHY_QCOM_QMP=y
CONFIG_PHY_QCOM_QMP_PCIE=y
CONFIG_I2C_HID_OF=m
CONFIG_KEYBOARD_GPIO=m
CONFIG_DRM_PANEL_SAMSUNG_ATNA33XC20=m
CFG

cp "$UBUNTU_CONFIG" "$OUT/.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" \
    "$SRC/arch/arm64/configs/qcom.config" "$OUT/glymur.config" >"$OUT/merge.log"
"${MAKE[@]}" olddefconfig >/dev/null

# Refuse to build if a required symbol did not survive olddefconfig.
missing=0
while IFS= read -r line; do
    case "$line" in
        CONFIG_*=*)
            if ! grep -qxF "$line" "$OUT/.config"; then
                printf 'config mismatch: wanted %s, got %s\n' "$line" \
                    "$(grep -E "^(# )?${line%%=*}[= ]" "$OUT/.config" || echo unset)" >&2
                missing=1
            fi
            ;;
    esac
done <"$OUT/glymur.config"
[ "$missing" -eq 0 ] || exit 1

"${MAKE[@]}" Image modules
KREL="$("${MAKE[@]}" -s kernelrelease)"
case "$KREL" in
    *-glymur"$SUFFIX") ;;
    *) printf 'unexpected kernel release %s (want *-glymur%s)\n' "$KREL" "$SUFFIX" >&2; exit 1 ;;
esac
STAGE="$OUT/stage"
rm -rf "$STAGE"
"${MAKE[@]}" INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install >/dev/null
cp "$OUT/arch/arm64/boot/Image" "$OUT/.config" "$OUT/System.map" "$STAGE/"

# HP device trees from the repository's dts/qcom/, compiled against this
# tree's glymur.dtsi and shipped next to the kernel (stage/dtbs/qcom/).
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if compgen -G "$REPO_DIR/dts/qcom/glymur-hp-*.dts" >/dev/null; then
    cp "$REPO_DIR"/dts/qcom/glymur-hp-* "$SRC/arch/arm64/boot/dts/qcom/"
    mkdir -p "$STAGE/dtbs/qcom"
    for dts in "$REPO_DIR"/dts/qcom/glymur-hp-*.dts; do
        dtb="qcom/$(basename "$dts" .dts).dtb"
        "${MAKE[@]}" "$dtb" >/dev/null
        cp "$OUT/arch/arm64/boot/dts/$dtb" "$STAGE/dtbs/qcom/"
    done
fi
tar -C "$STAGE" -czf "$OUT/glymur-kernel-$KREL.tar.gz" .
printf 'kernelrelease=%s\n' "$KREL"
sha256sum "$STAGE/Image" "$OUT/glymur-kernel-$KREL.tar.gz"
