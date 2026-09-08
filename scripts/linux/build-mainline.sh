#!/bin/bash
set -euo pipefail

SRC_DIR=".work/linux-mainline"
OUT_DIR=".work/build/mainline"
MODE="gcc"
BUILD_IMAGE=0
ALLOW_DIRTY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SRC_DIR="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
        --dtb-only) BUILD_IMAGE=0; shift ;;
        --image) BUILD_IMAGE=1; shift ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: Source directory $SRC_DIR does not exist."
    exit 1
fi

cd "$SRC_DIR"
HEAD_SHA=$(git rev-parse HEAD)
IS_DIRTY=$(git status --short)
echo "Source commit: $HEAD_SHA"

if [ -n "$IS_DIRTY" ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
    echo "Error: Source tree is dirty."
    exit 1
fi
cd - >/dev/null

mkdir -p "$OUT_DIR"
mkdir -p .work/logs

ABS_SRC="$(realpath "$SRC_DIR")"
ABS_OUT="$(realpath "$OUT_DIR")"

# Run configure
./scripts/linux/configure-glymur-build.sh --"$MODE" --source "$SRC_DIR" --out "$OUT_DIR"

echo "Building glymur-crd.dtb..."
LOG_FILE=".work/logs/build-mainline-crd.log"

if [ "$MODE" = "llvm" ]; then
    CMD="make -j$(nproc) -C $ABS_SRC O=$ABS_OUT ARCH=arm64 LLVM=1 qcom/glymur-crd.dtb"
else
    CMD="make -j$(nproc) -C $ABS_SRC O=$ABS_OUT ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-crd.dtb"
fi

echo "Running: $CMD"
if $CMD > "$LOG_FILE" 2>&1; then
    echo "Build glymur-crd.dtb: PASS"
else
    echo "Build glymur-crd.dtb: FAIL"
    exit 1
fi

if [ "$BUILD_IMAGE" -eq 1 ]; then
    echo "Building Image..."
    if [ "$MODE" = "llvm" ]; then
        IMG_CMD="make -j$(nproc) -C $ABS_SRC O=$ABS_OUT ARCH=arm64 LLVM=1 Image"
    else
        IMG_CMD="make -j$(nproc) -C $ABS_SRC O=$ABS_OUT ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image"
    fi
    echo "Running: $IMG_CMD"
    if $IMG_CMD >> "$LOG_FILE" 2>&1; then
        echo "Build Image: PASS"
    else
        echo "Build Image: FAIL"
        exit 1
    fi
fi

echo "Artifacts in $OUT_DIR"
