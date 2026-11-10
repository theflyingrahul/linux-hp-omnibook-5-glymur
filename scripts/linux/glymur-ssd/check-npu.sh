#!/usr/bin/env bash
set -u

# NPU (CDSP) through FastRPC, first look (issue #20). See README.md.
#   sudo bash check-npu.sh [dsp-dir]
# The kernel side is already there on every device-tree kernel: the CDSP
# runs HP's signed firmware and fastrpc binds its compute banks. What was
# missing is userspace: Qualcomm's FastRPC library (Debian/Ubuntu packages
# fastrpc-support and fastrpc-tests, from github.com/qualcomm/fastrpc) and
# the DSP-side shell, which HP ships in its Windows NPU driver
# (qcnspmcdm8480: fastrpc_shell_3, signed for this laptop). The USB kit
# stages those DSP files in npu/cdsp; dsp-dir defaults to where
# install-from-usb.sh puts them.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
DSP="${1:-/usr/share/qcom/glymur/HP/omnibook-5-16-bf1xxx/dsp/cdsp}"
OUT="/var/log/glymur/npu-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

sect "remote processors"
for r in /sys/class/remoteproc/remoteproc*; do
    printf '%s: %s %s %s\n' "${r##*/}" "$(cat "$r/name")" "$(cat "$r/state")" "$(cat "$r/firmware" 2>/dev/null)"
done
sect "FastRPC devices"
ls -l /dev/fastrpc-* 2>&1
journalctl -k -b --no-pager | grep -iE 'fastrpc|cdsp' | grep -v 'Adding to iommu group' | tail -20

sect "userspace"
command -v fastrpc_test >/dev/null 2>&1 || echo 'fastrpc_test missing: run sudo bash setup-npu.sh first'
dpkg -l 'fastrpc*' 'libfastrpc*' 'hexagon-dsp*' 2>/dev/null | grep '^ii'
ls -l "$DSP" 2>&1 | head -30

sect "FastRPC test on the CDSP"
export ADSP_LIBRARY_PATH="$DSP:/usr/lib/dsp/cdsp:/usr/share/qcom/glymur/dsp/cdsp"
export DSP_LIBRARY_PATH="$ADSP_LIBRARY_PATH"
# The healthcheck only looks in its configured libdir and /usr/lib.
export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if command -v fastrpc_test >/dev/null 2>&1; then
    if command -v fastrpc-healthcheck >/dev/null 2>&1; then
        echo '--- fastrpc-healthcheck'
        timeout 60 fastrpc-healthcheck 2>&1 | tail -40
    fi
    CAPS="$(dirname "$0")/npu-caps.c"
    if [ -f "$CAPS" ] && command -v gcc >/dev/null 2>&1; then
        echo '--- npu-caps (the CDSP asked what it is)'
        gcc -Wall -o /tmp/npu-caps "$CAPS" -I/usr/include/fastrpc -lcdsprpc 2>&1 | head -5
        timeout 60 /tmp/npu-caps 2>&1
    fi
    fastrpc_test -h 2>&1 | head -15
    for args in "-d 3 -U 1" "-d 3 -U 0"; do
        echo "--- fastrpc_test $args"
        timeout 60 fastrpc_test $args 2>&1 | tail -25
        echo "exit $?"
    done
else
    echo 'no fastrpc_test'
fi
journalctl -k --no-pager --since '-3 min' | grep -iE 'fastrpc|smmu|cdsp' | tail -20
echo "log: $OUT"
