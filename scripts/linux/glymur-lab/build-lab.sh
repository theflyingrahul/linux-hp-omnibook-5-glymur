#!/usr/bin/env bash
set -euo pipefail

# Build the display-lab kit in WSL, from ~/glymur-build, against the kernel
# build the SSD runs (7.3.0-rc2-glymur-3):
#
#   scripts/linux/glymur-lab/build-lab.sh [SRC] [OUT] [KIT]
#
# Builds and checks, before anything reaches the laptop:
#   - the display-lab DTB (with overlay symbols) and its two overlays; each
#     overlay is applied offline with fdtoverlay and the merged tree must
#     pass the GPIO allow-list check with the eDP pins in use;
#   - glymur_lab.ko and the instrumented phy-qcom-edp-lab.ko, whose
#     vermagic must be the target release;
# and assembles KIT with the run scripts, HP's Bluetooth pair and
# SHA256SUMS.

SRC="$(realpath "${1:-.work/linux-qcom-next-glymur}")"
OUT="$(realpath "${2:-.work/build/qcom-next-glymur}")"
KIT="${3:-.work/lab-kit}"
KREL=7.3.0-rc2-glymur-3
SUFFIX=-3
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
DTS="$OUT/arch/arm64/boot/dts/qcom"
MAKE=(make -C "$SRC" "O=$OUT" ARCH=arm64 "LOCALVERSION=$SUFFIX")
CHECK="$REPO/scripts/linux/check-dt-gpio-allowlist.py"
LAB=mahua-hp-omnibook-5-bf1xxx-lab

grep -q "\"$KREL\"" "$OUT/include/generated/utsrelease.h" ||
    { echo "$OUT is not the $KREL build" >&2; exit 1; }

# Device trees.
rm -f "$SRC"/arch/arm64/boot/dts/qcom/glymur-hp-omnibook-5-bf1xxx*
cp "$REPO"/dts/qcom/*-hp-* "$SRC/arch/arm64/boot/dts/qcom/"
rm -f "$DTS/$LAB.dtb" "$DTS/$LAB-display.dtbo" "$DTS/$LAB-rails.dtbo"
"${MAKE[@]}" "DTC_FLAGS_$LAB=-@" "qcom/$LAB.dtb" "qcom/$LAB-display.dtbo" \
    "qcom/$LAB-rails.dtbo" 2>&1 | grep -v 'dtbo is not applied' || true
for f in "$LAB.dtb" "$LAB-display.dtbo" "$LAB-rails.dtbo"; do
    [ -s "$DTS/$f" ] || { echo "missing $f" >&2; exit 1; }
done
fdtget "$DTS/$LAB.dtb" /__symbols__ mdss_dp3_out >/dev/null ||
    { echo 'lab DTB has no overlay symbols' >&2; exit 1; }

python3 "$CHECK" --spare 18,70,119 "$DTS/$LAB.dtb" | grep -E 'OK|FAIL'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$OUT/scripts/dtc/fdtoverlay" -i "$DTS/$LAB.dtb" -o "$tmp/display.dtb" "$DTS/$LAB-display.dtbo"
"$OUT/scripts/dtc/fdtoverlay" -i "$DTS/$LAB.dtb" -o "$tmp/display-rails.dtb" \
    "$DTS/$LAB-display.dtbo" "$DTS/$LAB-rails.dtbo"
python3 "$CHECK" "$tmp/display.dtb" "$tmp/display-rails.dtb" | grep -E 'OK|FAIL'
for n in /soc@0/clock-controller@af00000 /soc@0/display-subsystem@ae00000 /soc@0/phy@faac00 /regulator-edp; do
    [ "$(fdtget "$tmp/display.dtb" "$n" status)" = okay ] ||
        { echo "overlay did not enable $n" >&2; exit 1; }
done
fdtget -l "$tmp/display-rails.dtb" /soc@0/rsc@18900000 | grep -q regulators-1 ||
    { echo 'rails overlay did not add the regulators' >&2; exit 1; }

# Modules.
build="$(realpath -m .work/lab-build)"
rm -rf "$build"
mkdir -p "$build/lab"
cp "$HERE/glymur_lab.c" "$build/lab/"
echo 'obj-m += glymur_lab.o' >"$build/lab/Makefile"
python3 "$HERE/make-phy-edp-lab.py" "$SRC" "$build/phy"
for d in lab phy; do
    "${MAKE[@]}" "M=$build/$d" modules
done
for ko in "$build/lab/glymur_lab.ko" "$build/phy/phy-qcom-edp-lab.ko"; do
    vm="$(modinfo -F vermagic "$ko" | cut -d' ' -f1)"
    [ "$vm" = "$KREL" ] || { echo "$ko vermagic $vm, want $KREL" >&2; exit 1; }
done

# Kit.
rm -rf "$KIT"
mkdir -p "$KIT/bt"
cp "$DTS/$LAB.dtb" "$DTS/$LAB-display.dtbo" "$DTS/$LAB-rails.dtbo" "$KIT/"
cp "$build/lab/glymur_lab.ko" "$build/phy/phy-qcom-edp-lab.ko" "$KIT/"
cp "$HERE/start-lab.sh" "$HERE/glymur-lab-run.sh" "$HERE/analyze-fw-snapshot.py" "$KIT/"
cp "$REPO"/boards/hp-omnibook-5-16-bf1xxx/firmware/qcbluetooth8480_WHQL/clnbt* "$KIT/bt/"
(cd "$KIT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs sha256sum >SHA256SUMS)
echo "kit ready: $KIT"
ls -lR "$KIT"
