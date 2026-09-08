#!/bin/bash
set -euo pipefail

MODE="gcc"
TARGET_ELITEBOOK=0
TARGET_OMNIBOOK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
        --elitebook) TARGET_ELITEBOOK=1; shift ;;
        --omnibook-ultra) TARGET_OMNIBOOK=1; shift ;;
        --all) TARGET_ELITEBOOK=1; TARGET_OMNIBOOK=1; shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

if [ "$TARGET_ELITEBOOK" -eq 1 ]; then
    echo "=== Building EliteBook Reference DTB ==="
    SRC_DIR=".work/linux-elitebook"
    OUT_DIR=".work/build/elitebook"
    if [ ! -d "$SRC_DIR" ]; then
        echo "Error: $SRC_DIR does not exist. Ensure worktree is prepared."
        exit 1
    fi
    mkdir -p "$OUT_DIR" .work/logs
    ./scripts/linux/configure-glymur-build.sh --$MODE --source "$SRC_DIR" --out "$OUT_DIR"
    
    if [ "$MODE" = "llvm" ]; then
        CMD="make -C $SRC_DIR O=../${OUT_DIR#*/} ARCH=arm64 LLVM=1 qcom/glymur-hp-elitebook-x-g2q.dtb"
    else
        CMD="make -C $SRC_DIR O=../${OUT_DIR#*/} ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-hp-elitebook-x-g2q.dtb"
    fi
    echo "Running: $CMD"
    if $CMD > ".work/logs/build-elitebook.log" 2>&1; then
        echo "Build EliteBook DTB: PASS"
    else
        echo "Build EliteBook DTB: BLOCKED (Toolchain unavailable or error)"
    fi
    echo "*** WARNING: REFERENCE BUILD ONLY - DO NOT BOOT THIS DTB ON THE TARGET OMNIBOOK 5 ***"
fi

if [ "$TARGET_OMNIBOOK" -eq 1 ]; then
    echo "=== Building OmniBook Ultra Reference DTB ==="
    SRC_DIR=".work/linux-omnibook-ultra"
    OUT_DIR=".work/build/omnibook-ultra"
    if [ ! -d "$SRC_DIR" ]; then
        echo "Error: $SRC_DIR does not exist. Ensure worktree is prepared."
        exit 1
    fi
    mkdir -p "$OUT_DIR" .work/logs
    ./scripts/linux/configure-glymur-build.sh --$MODE --source "$SRC_DIR" --out "$OUT_DIR"
    
    if [ "$MODE" = "llvm" ]; then
        CMD="make -C $SRC_DIR O=../${OUT_DIR#*/} ARCH=arm64 LLVM=1 qcom/glymur-hp-omnibook-ultra-kg0xxx.dtb"
    else
        CMD="make -C $SRC_DIR O=../${OUT_DIR#*/} ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/glymur-hp-omnibook-ultra-kg0xxx.dtb"
    fi
    echo "Running: $CMD"
    if $CMD > ".work/logs/build-omnibook.log" 2>&1; then
        echo "Build OmniBook Ultra DTB: PASS"
    else
        echo "Build OmniBook Ultra DTB: BLOCKED (Toolchain unavailable or error)"
    fi
    echo "*** WARNING: REFERENCE BUILD ONLY - DO NOT BOOT THIS DTB ON THE TARGET OMNIBOOK 5 ***"
fi
