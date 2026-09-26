#!/usr/bin/env bash
set -euo pipefail

# arm64 /proc/cpuinfo has no "model name", so GNOME Settings (libgtop) shows
# "(null) x 12". Bind-mount a copy of /proc/cpuinfo that adds the SMBIOS
# processor Version string to each CPU block. Undo with: umount /proc/cpuinfo
# Usage: glymur-cpuinfo-model.sh [--undo]

OUT=/run/glymur-cpuinfo

if [ "${1:-}" = --undo ]; then
    umount /proc/cpuinfo 2>/dev/null || true
    exit 0
fi

if grep -q '^model name' /proc/cpuinfo; then
    echo "/proc/cpuinfo already has a model name"
    exit 0
fi

MODEL=$(dmidecode -s processor-version | head -n 1 | sed 's/[[:space:]]*$//')
if [ -z "$MODEL" ]; then
    echo "SMBIOS has no processor version; leaving /proc/cpuinfo alone" >&2
    exit 1
fi

awk -v model="$MODEL" '
    /^processor[[:space:]]*:/ { print; print "model name\t: " model; next }
    { print }
' /proc/cpuinfo >"$OUT"
mount --bind "$OUT" /proc/cpuinfo
echo "model name: $MODEL"
