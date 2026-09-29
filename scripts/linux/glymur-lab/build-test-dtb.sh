#!/usr/bin/env bash
set -euo pipefail

# Build one HP test device tree in WSL, from ~/glymur-build, against the
# kernel build the SSD runs (7.3.0-rc2-glymur-3), for booting from the USB
# with that kernel:
#
#   scripts/linux/glymur-lab/build-test-dtb.sh NAME [SRC] [OUT] [DEST]
#
# NAME is a dts/qcom/NAME.dts in this repository. The DTB must pass the GPIO
# allow-list check; its eDP endpoint and model are printed for review, and
# it is copied to DEST (default .work/test-dtbs) with a SHA256SUMS line.

NAME="${1:?usage: build-test-dtb.sh NAME [SRC] [OUT] [DEST]}"
SRC="$(realpath "${2:-.work/linux-qcom-next-glymur}")"
OUT="$(realpath "${3:-.work/build/qcom-next-glymur}")"
DEST="${4:-.work/test-dtbs}"
KREL=7.3.0-rc2-glymur-3
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
DTS="$OUT/arch/arm64/boot/dts/qcom"
CHECK="$REPO/scripts/linux/check-dt-gpio-allowlist.py"

[ -f "$REPO/dts/qcom/$NAME.dts" ] || { echo "no dts/qcom/$NAME.dts" >&2; exit 1; }
grep -q "\"$KREL\"" "$OUT/include/generated/utsrelease.h" ||
    { echo "$OUT is not the $KREL build" >&2; exit 1; }

rm -f "$SRC"/arch/arm64/boot/dts/qcom/glymur-hp-omnibook-5-bf1xxx*
cp "$REPO"/dts/qcom/*-hp-* "$SRC/arch/arm64/boot/dts/qcom/"
rm -f "$DTS/$NAME.dtb"
make -C "$SRC" "O=$OUT" ARCH=arm64 LOCALVERSION=-3 "qcom/$NAME.dtb"
[ -s "$DTS/$NAME.dtb" ] || { echo "missing $NAME.dtb" >&2; exit 1; }
grep -q "\"$KREL\"" "$OUT/include/generated/utsrelease.h" ||
    { echo "the build changed the kernel release" >&2; exit 1; }

python3 "$CHECK" "$DTS/$NAME.dtb"
echo "model: $(fdtget "$DTS/$NAME.dtb" / model)"
"$OUT/scripts/dtc/dtc" -q -I dtb -O dts "$DTS/$NAME.dtb" |
    grep -B1 -A2 'link-frequencies'

mkdir -p "$DEST"
cp "$DTS/$NAME.dtb" "$DEST/"
(cd "$DEST" && sha256sum "$NAME.dtb" | tee "$NAME.dtb.sha256")
