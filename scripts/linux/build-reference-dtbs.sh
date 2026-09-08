#!/bin/bash
set -euo pipefail

MODE="gcc"
ALLOW_DIRTY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

build_dtb() {
    local label="$1"
    local src="$2"
    local dtb_target="$3"
    
    echo "--- Building $label ---"
    if [ ! -d "$src" ]; then
        echo "Error: Source directory $src not found."
        return 1
    fi
    
    cd "$src"
    local is_dirty
    is_dirty=$(git status --short)
    if [ -n "$is_dirty" ] && [ "$ALLOW_DIRTY" -eq 0 ]; then
        echo "Error: Tree is dirty. Aborting."
        cd - >/dev/null
        return 1
    fi
    cd - >/dev/null
    
    local out=".work/build/$label"
    mkdir -p "$out"
    local abs_src
    local abs_out
    abs_src="$(realpath "$src")"
    abs_out="$(realpath "$out")"
    
    ./scripts/linux/configure-glymur-build.sh --"$MODE" --source "$src" --out "$out"
    
    local cmd
    if [ "$MODE" = "llvm" ]; then
        cmd="make -j$(nproc) -C $abs_src O=$abs_out ARCH=arm64 LLVM=1 $dtb_target"
    else
        cmd="make -j$(nproc) -C $abs_src O=$abs_out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- $dtb_target"
    fi
    
    echo "Running: $cmd"
    if $cmd > ".work/logs/build-${label}.log" 2>&1; then
        echo "Build $dtb_target: PASS"
    else
        echo "Build $dtb_target: FAIL"
    fi
}

mkdir -p .work/logs
build_dtb "elitebook-v5" ".work/linux-elitebook" "qcom/glymur-hp-elitebook-x-g2q.dtb"
build_dtb "omnibook-ultra-v1" ".work/linux-omnibook-ultra" "qcom/glymur-hp-omnibook-ultra-kg0xxx.dtb"
