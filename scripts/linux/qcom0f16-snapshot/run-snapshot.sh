#!/usr/bin/env bash
set -u

# Run the read-only GENI UART / BT_EN snapshot on the SSD install.
#   sudo bash run-snapshot.sh <dir-with-qcom0f16_snapshot.ko-and-SHA256SUMS> [out-dir]
# The module is built against 7.3.0-rc2-glymur on the build host and staged
# on the USB (glymur-tools/qcom0f16-snapshot/). It binds nothing and writes
# no registers; see qcom0f16_snapshot.c. Output: <out-dir>/qcom0f16-snapshot-<time>.txt

KIT="${1:?usage: run-snapshot.sh <kit-dir> [out-dir]}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIR="${2:-$REPO/.work}"
KO="$KIT/qcom0f16_snapshot.ko"

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
(cd "$KIT" && sha256sum --quiet -c SHA256SUMS) || { echo 'module hash mismatch' >&2; exit 1; }
want="$(modinfo -F vermagic "$KO" | cut -d' ' -f1)"
[ "$want" = "$(uname -r)" ] || { echo "module is for $want, running $(uname -r)" >&2; exit 1; }
for d in /sys/bus/platform/devices/QCOM0F16:*; do
    if [ -e "$d/driver" ]; then
        echo "$(basename "$d") is already bound to $(basename "$(readlink "$d/driver")"); not loading" >&2
        exit 1
    fi
done
lsmod | grep -q '^qcom0f16_snapshot' && rmmod qcom0f16_snapshot

mkdir -p "$OUT_DIR"
out="$OUT_DIR/qcom0f16-snapshot-$(date +%Y%m%dT%H%M%S).txt"
{
    echo "# kernel $(uname -r)"
    for d in /sys/bus/platform/devices/QCOM0F16:* /sys/bus/platform/devices/QCOM0F6B:*; do
        printf '# %s %s\n' "$(basename "$d")" "$(cat "$d/firmware_node/path" 2>/dev/null)"
    done
} >"$out"
marker="qcom0f16-snapshot-$$-$(date +%s)"
echo "$marker" >/dev/kmsg
insmod "$KO" snapshot=1
sleep 1
rmmod qcom0f16_snapshot
dmesg | sed -n "/$marker/,\$p" | grep -E 'qcom0f16|QCOM0F16|snapshot' >>"$out"
cat "$out"
echo "Saved $out"
