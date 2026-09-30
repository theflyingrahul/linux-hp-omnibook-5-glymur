#!/usr/bin/env bash
set -euo pipefail

# Build the qcom-next boot kernel for the SSD root. See README.md.

SRC="${1:-.work/linux-qcom-next-glymur}"
OUT="${2:-.work/build/qcom-next-glymur}"
JOBS="${3:-8}"
UBUNTU_CONFIG="${UBUNTU_CONFIG:-/usr/src/linux-headers-7.0.0-30-generic/.config}"
# GLYMUR_SUFFIX gives each build its own release, e.g. 7.3.0-rc2-glymur-2.
SUFFIX="${GLYMUR_SUFFIX:-}"
case "$SUFFIX" in
    '' | -[A-Za-z0-9]*) ;;
    *) printf 'GLYMUR_SUFFIX must start with - (got %s)\n' "$SUFFIX" >&2; exit 2 ;;
esac

SRC="$(realpath "$SRC")"
mkdir -p "$OUT"
OUT="$(realpath "$OUT")"
# Empty LOCALVERSION: no "+" for an untagged tree.
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
# Device-tree boot without an initramfs: built-in providers.
CONFIG_CLK_GLYMUR_GCC=y
CONFIG_CLK_GLYMUR_TCSRCC=y
CONFIG_PINCTRL_GLYMUR=y
CONFIG_INTERCONNECT_QCOM_GLYMUR=y
CONFIG_PHY_QCOM_QMP=y
CONFIG_PHY_QCOM_QMP_PCIE=y
# GPU clock controllers, built in to beat the deferred-probe timeout.
CONFIG_CLK_GLYMUR_GPUCC=y
CONFIG_I2C_HID_OF=m
CONFIG_KEYBOARD_GPIO=m
CONFIG_DRM_PANEL_SAMSUNG_ATNA33XC20=m
CONFIG_EC_HP_OMNIBOOK5=m
CFG

cp "$UBUNTU_CONFIG" "$OUT/.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" \
    "$SRC/arch/arm64/configs/qcom.config" "$OUT/glymur.config" >"$OUT/merge.log"
"${MAKE[@]}" olddefconfig >/dev/null

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

# HP DTBs, each checked against the GPIO allow-list.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$REPO_DIR/scripts/linux/check-dt-gpio-allowlist.py"
if compgen -G "$REPO_DIR/dts/qcom/*-hp-*.dts" >/dev/null; then
    rm -f "$SRC"/arch/arm64/boot/dts/qcom/glymur-hp-omnibook-5-bf1xxx*
    cp "$REPO_DIR"/dts/qcom/*-hp-* "$SRC/arch/arm64/boot/dts/qcom/"
    mkdir -p "$STAGE/dtbs/qcom"
    python3 -c 'import libfdt' 2>/dev/null ||
        echo 'warning: python3-libfdt missing; GPIO allow-list not checked' >&2
    for dts in "$REPO_DIR"/dts/qcom/*-hp-*.dts; do
        # Lab and test DTBs are built by glymur-lab/.
        case "$dts" in *-lab.dts | *-edp-2lane.dts) continue ;; esac
        dtb="$OUT/arch/arm64/boot/dts/qcom/$(basename "$dts" .dts).dtb"
        rm -f "$dtb"
        "${MAKE[@]}" "qcom/$(basename "$dtb")" >/dev/null
        if python3 -c 'import libfdt' 2>/dev/null && ! python3 "$CHECK" "$dtb" >/dev/null; then
            python3 "$CHECK" "$dtb" | grep FAIL >&2
            exit 1
        fi
        cp "$dtb" "$STAGE/dtbs/qcom/"
    done
fi
tar -C "$STAGE" -czf "$OUT/glymur-kernel-$KREL.tar.gz" .
printf 'kernelrelease=%s\n' "$KREL"
sha256sum "$STAGE/Image" "$OUT/glymur-kernel-$KREL.tar.gz"
