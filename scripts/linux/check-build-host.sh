#!/bin/bash
set -euo pipefail

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
gcc_missing=""
for t in aarch64-linux-gnu-gcc flex bison bc pkg-config; do
    if ! has_cmd "$t"; then gcc_missing="$gcc_missing $t"; fi
done
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
