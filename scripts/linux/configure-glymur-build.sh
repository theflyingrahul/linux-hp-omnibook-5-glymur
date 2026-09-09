#!/bin/bash
set -euo pipefail

OUT_DIR=".work/build/mainline"
SRC_DIR=".work/linux-mainline"
MODE="gcc"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --source) SRC_DIR="$2"; shift 2 ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: Source directory $SRC_DIR does not exist."
    exit 1
fi

# Convert out_dir to absolute for make if needed, but since we run from repo root,
# we can just use absolute paths to be safe.
ABS_SRC="$(realpath "$SRC_DIR")"
mkdir -p "$OUT_DIR"
ABS_OUT="$(realpath "$OUT_DIR")"

echo "Source: $SRC_DIR"
echo "Output: $OUT_DIR"
echo "Mode: $MODE"

echo "Generating arm64 defconfig..."
if [ "$MODE" = "llvm" ]; then
    make -C "$ABS_SRC" O="$ABS_OUT" ARCH=arm64 LLVM=1 defconfig
else
    make -C "$ABS_SRC" O="$ABS_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
fi

CONFIG_FILE="$ABS_OUT/.config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: .config not generated."
    exit 1
fi

echo "Verifying Required Glymur Symbols..."

# Save previous value of CONFIG_QCOM_CPUCP_MBOX to record it
grep CONFIG_QCOM_CPUCP_MBOX "$CONFIG_FILE" || echo "CONFIG_QCOM_CPUCP_MBOX is unset"

"$ABS_SRC/scripts/config" --file "$CONFIG_FILE" \
    --enable CONFIG_QCOM_CPUCP_MBOX \
    --enable CONFIG_INTERCONNECT_QCOM_GLYMUR \
    --enable CONFIG_PINCTRL_GLYMUR

if [ "$MODE" = "llvm" ]; then
    make -C "$ABS_SRC" O="$ABS_OUT" ARCH=arm64 LLVM=1 olddefconfig
else
    make -C "$ABS_SRC" O="$ABS_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
fi

grep CONFIG_QCOM_CPUCP_MBOX "$CONFIG_FILE" || echo "WARNING: CONFIG_QCOM_CPUCP_MBOX not found after olddefconfig"
echo "Configuration complete."
