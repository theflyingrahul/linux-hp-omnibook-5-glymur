#!/usr/bin/env bash
set -euo pipefail

# Compile Qualcomm's integration kernel with its published Debian config
# fragments. This validates source and toolchain only; it does not create an
# HP OmniBook 5 bootable image or write to removable/internal storage.

SOURCE_DIR=".work/linux-qcom-next"
RECIPES_DIR=".work/qcom-deb-images"
OUTPUT_DIR=".work/build/qcom-next"
JOBS=2

while (( $# )); do
    case "$1" in
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --recipes) RECIPES_DIR="$2"; shift 2 ;;
        --out) OUTPUT_DIR="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' '--jobs must be a positive integer' >&2
    exit 2
fi
if [[ ! -f "$SOURCE_DIR/Makefile" ||
      ! -f "$SOURCE_DIR/arch/arm64/configs/prune.config" ||
      ! -f "$SOURCE_DIR/arch/arm64/configs/qcom.config" ||
      ! -d "$RECIPES_DIR/kernel-configs" ]]; then
    printf '%s\n' 'Missing Qualcomm kernel source or config recipes' >&2
    exit 1
fi

SOURCE_DIR="$(realpath "$SOURCE_DIR")"
RECIPES_DIR="$(realpath "$RECIPES_DIR")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(realpath "$OUTPUT_DIR")"

if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ||
      -n "$(git -C "$RECIPES_DIR" status --porcelain)" ]]; then
    printf '%s\n' 'Source and recipe checkouts must be clean' >&2
    exit 1
fi

mapfile -t EXTRA_FRAGMENTS < <(find "$RECIPES_DIR/kernel-configs" -maxdepth 1 \
    -type f -name '*.config' | sort)
if (( ${#EXTRA_FRAGMENTS[@]} == 0 )); then
    printf '%s\n' 'No Qualcomm kernel-configs/*.config fragments found' >&2
    exit 1
fi

printf 'Kernel source: %s\n' "$(git -C "$SOURCE_DIR" rev-parse HEAD)"
printf 'Image recipes: %s\n' "$(git -C "$RECIPES_DIR" rev-parse HEAD)"
printf 'Output: %s; jobs: %s\n' "$OUTPUT_DIR" "$JOBS"

MAKE=(make -C "$SOURCE_DIR" "O=$OUTPUT_DIR" ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu-)
"${MAKE[@]}" defconfig
"$SOURCE_DIR/scripts/kconfig/merge_config.sh" -m -r -O "$OUTPUT_DIR" \
    "$OUTPUT_DIR/.config" "$SOURCE_DIR/arch/arm64/configs/prune.config" \
    "$SOURCE_DIR/arch/arm64/configs/qcom.config" "${EXTRA_FRAGMENTS[@]}"
"${MAKE[@]}" olddefconfig
"${MAKE[@]}" "-j$JOBS" Image qcom/glymur-crd.dtb

printf '%s\n' 'Build complete. The CRD DTB is a reference artifact, not an HP DTB.'
