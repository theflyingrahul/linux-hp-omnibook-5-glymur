#!/bin/bash
set -u

MODE="all"
if [ "${1:-}" = "--dt-only" ]; then
    MODE="dt"
elif [ "${1:-}" = "--kernel" ]; then
    MODE="kernel"
fi

echo "--- Host Information ---"
uname -a
uname -m
if [ -f /etc/os-release ]; then
    grep PRETTY_NAME /etc/os-release
fi
echo ""

echo "--- Tool Inventory ---"
TOOLS="git make python3 clang ld.lld gcc aarch64-linux-gnu-gcc dtc b4 flex bison bc openssl pahole pkg-config"

missing_any=0
has_clang=1
has_gcc_cross=1
has_dtc=1

for t in $TOOLS; do
    if command -v "$t" >/dev/null 2>&1; then
        echo "[OK] $t"
    else
        echo "[MISSING] $t"
        missing_any=1
        if [ "$t" = "clang" ]; then has_clang=0; fi
        if [ "$t" = "aarch64-linux-gnu-gcc" ]; then has_gcc_cross=0; fi
        if [ "$t" = "dtc" ]; then has_dtc=0; fi
    fi
done
echo ""

echo "--- Summary ---"
can_dt=0
can_kernel=0

if [ $has_dtc -eq 1 ]; then
    if [ $has_clang -eq 1 ] || [ $has_gcc_cross -eq 1 ]; then
        can_dt=1
    fi
fi

if [ $has_clang -eq 1 ] || [ $has_gcc_cross -eq 1 ]; then
    # In reality, need flex, bison, bc, openssl etc. for kernel
    can_kernel=1
fi

if [ $can_dt -eq 1 ]; then
    echo "ready for DT-only build"
else
    echo "missing tools for DT-only build"
fi

if [ $can_kernel -eq 1 ]; then
    echo "ready for kernel Image build"
else
    echo "missing tools for kernel Image build"
fi

if [ $missing_any -eq 1 ]; then
    echo "missing tools"
fi

if [ "$MODE" = "dt" ] && [ $can_dt -eq 0 ]; then
    exit 1
elif [ "$MODE" = "kernel" ] && [ $can_kernel -eq 0 ]; then
    exit 1
fi

exit 0
