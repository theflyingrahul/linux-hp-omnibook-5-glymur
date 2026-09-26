#!/bin/bash
set -euo pipefail

MODE="all"
case "${1:-}" in
    "") ;;
    --dt-only) MODE="dt" ;;
    --kernel) MODE="kernel" ;;
    --help|-h)
        echo "Usage: $0 [--dt-only|--kernel]"
        exit 0
        ;;
    *)
        echo "Usage: $0 [--dt-only|--kernel]" >&2
        exit 2
        ;;
esac

echo "Host:"
if [ -f /etc/os-release ]; then
    grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"' | awk '{print "    " $0}'
fi
uname -m | awk '{print "    " $0}'
echo ""

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo "GCC ARM64 cross-build:"
shared_missing=""
for t in make flex bison bc pkg-config; do
    if ! has_cmd "$t"; then shared_missing="$shared_missing $t"; fi
done
gcc_compiler_missing=""
if ! has_cmd aarch64-linux-gnu-gcc; then gcc_compiler_missing=" aarch64-linux-gnu-gcc"; fi
# Kbuild compiles host tools (including scripts/dtc) with HOSTCC=gcc unless
# LLVM=1 is used, so a cross compiler alone is not sufficient.
if ! has_cmd gcc; then gcc_compiler_missing="$gcc_compiler_missing gcc"; fi
gcc_missing="$gcc_compiler_missing$shared_missing"
if [ -n "$gcc_missing" ]; then
    echo "    BLOCKED"
    echo "    missing:$gcc_missing"
else
    echo "    READY"
fi
echo ""

echo "LLVM ARM64 build:"
llvm_missing=""
for t in clang ld.lld llvm-ar llvm-nm llvm-objcopy; do
    if ! has_cmd "$t"; then llvm_missing="$llvm_missing $t"; fi
done
llvm_compiler_missing="$llvm_missing"
llvm_missing="$llvm_compiler_missing$shared_missing"
if [ -n "$llvm_missing" ]; then
    echo "    BLOCKED"
    echo "    missing:$llvm_missing"
else
    echo "    READY"
fi
echo ""

echo "DTB build:"
dt_missing=""
if ! has_cmd dtc; then dt_missing=" dtc"; fi
if [ -n "$dt_missing" ]; then
    echo "    BLOCKED"
    echo "    missing:$dt_missing"
else
    echo "    READY"
fi
echo ""

echo "Patch workflow:"
if has_cmd git; then
    echo "    git: READY"
else
    echo "    git: MISSING"
fi
if has_cmd b4; then
    echo "    b4: READY"
else
    echo "    b4: MISSING"
fi

if [ "$MODE" = "dt" ]; then
    if [ -n "$shared_missing" ] || [ -n "$dt_missing" ] || { [ -n "$gcc_compiler_missing" ] && [ -n "$llvm_compiler_missing" ]; }; then
        exit 1
    fi
elif [ "$MODE" = "kernel" ]; then
    if [ -n "$shared_missing" ] || { [ -n "$gcc_compiler_missing" ] && [ -n "$llvm_compiler_missing" ]; }; then
        exit 1
    fi
fi
