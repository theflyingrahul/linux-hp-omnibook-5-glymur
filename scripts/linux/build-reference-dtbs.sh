#!/bin/bash
set -euo pipefail

MODE="gcc"
ALLOW_DIRTY=0
JOBS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llvm) MODE="llvm"; shift ;;
        --gcc) MODE="gcc"; shift ;;
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

CPUS=$(nproc)
MEM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if [ -z "$MEM_KB" ]; then
    MEM_KB=$(awk '/MemFree/ {print $2}' /proc/meminfo)
fi
MEM_MB=$((MEM_KB / 1024))
REASON=""

if [ -n "$JOBS" ]; then
    REASON="Explicitly requested via --jobs"
elif [[ "${MAKEFLAGS:-}" == *"-j"* ]]; then
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

JOB_FLAG=""
if [ -n "$JOBS" ]; then
    JOB_FLAG="-j$JOBS"
fi

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
        cmd="make $JOB_FLAG -C $abs_src O=$abs_out ARCH=arm64 LLVM=1 $dtb_target"
    else
        cmd="make $JOB_FLAG -C $abs_src O=$abs_out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- $dtb_target"
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
