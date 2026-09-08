#!/bin/bash
set -euo pipefail

SRC_DIR=".work/linux-mainline"
OUT_DIR=".work/build/mainline"
MODE="gcc"
BUILD_IMAGE=0
ALLOW_DIRTY=0
JOBS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SRC_DIR="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
        --dtb-only) BUILD_IMAGE=0; shift ;;
        --image) BUILD_IMAGE=1; shift ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        --jobs) 
            JOBS="$2"
            if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [ "$JOBS" -lt 1 ]; then
                echo "Error: --jobs requires a positive integer."
                exit 1
            fi
            shift 2 ;;
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

# Job calculation logic
CPUS=$(nproc)
MEM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
# Fallback to MemFree if MemAvailable is missing
if [ -z "$MEM_KB" ]; then
    MEM_KB=$(awk '/MemFree/ {print $2}' /proc/meminfo)
fi
MEM_MB=$((MEM_KB / 1024))
REASON=""

if [ -n "$JOBS" ]; then
    REASON="Explicitly requested via --jobs"
elif [[ "${MAKEFLAGS:-}" == *"-j"* ]]; then
    # Respect MAKEFLAGS if it contains -j, we don't supply our own -j
    JOBS=""
    REASON="Deferred to MAKEFLAGS"
else
    # Heuristic: ~1500MB RAM per compile job max, up to CPUS, capped at 16
    MAX_MEM_JOBS=$((MEM_MB / 1500))
    if [ "$MAX_MEM_JOBS" -lt 1 ]; then
        MAX_MEM_JOBS=1
    fi
    JOBS=$CPUS
    if [ "$JOBS" -gt "$MAX_MEM_JOBS" ]; then
        JOBS=$MAX_MEM_JOBS
        REASON="Memory constrained (Available: ${MEM_MB}MB, budgeting ~1.5GB/job)"
    elif [ "$JOBS" -gt 16 ]; then
        JOBS=16
        REASON="Capped at reasonable maximum of 16"
    else
        REASON="Bounded by CPU count"
    fi
fi

echo "--- Build Parallelism Info ---"
echo "Detected CPUs: $CPUS"
echo "Detected available memory: ${MEM_MB}MB"
if [ -n "$JOBS" ]; then
    echo "Selected job count: $JOBS"
else
    echo "Selected job count: MAKEFLAGS"
fi
echo "Reason: $REASON"
echo "------------------------------"

if [ "$BUILD_IMAGE" -eq 1 ]; then
    echo "Note: Full kernel builds are memory intensive."
    echo "Avoid running simultaneous GCC and LLVM Image builds unless sufficient RAM is known to be available."
fi

JOB_FLAG=""
if [ -n "$JOBS" ]; then
    JOB_FLAG="-j$JOBS"
fi

# Run configure
./scripts/linux/configure-glymur-build.sh --"$MODE" --source "$SRC_DIR" --out "$OUT_DIR"

echo "Building glymur-crd.dtb..."
LOG_FILE=".work/logs/build-mainline-crd.log"

if [ "$MODE" = "llvm" ]; then
    CMD="make $JOB_FLAG -C $ABS_SRC O=$ABS_OUT ARCH=arm64 LLVM=1 qcom/glymur-crd.dtb"
else
    CMD="make $JOB_FLAG -C $ABS_SRC O=$ABS_OUT ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-crd.dtb"
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
        IMG_CMD="make $JOB_FLAG -C $ABS_SRC O=$ABS_OUT ARCH=arm64 LLVM=1 Image"
    else
        IMG_CMD="make $JOB_FLAG -C $ABS_SRC O=$ABS_OUT ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image"
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
