#!/usr/bin/env bash
set -u

# USB check for the "device tree (GPU and USB-A test)" boot: controller,
# PHYs, enumeration and link speed of the right-hand USB-A port, written to
# /var/log/glymur/usb-test-<time>.txt. If the port works it can be run
# straight from the USB stick:
#
#   sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/check-usb.sh"
#
# If the port does not work, boot any other entry afterwards and run
#   sudo bash check-usb.sh --previous
# for the same report from the previous boot's kernel log.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
B=0
[ "${1:-}" = --previous ] && B=-1
OUT="/var/log/glymur/usb-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

sect system
uname -a
[ "$B" = 0 ] && { tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo; }
journalctl -k -b "$B" --no-pager | grep -m1 'Machine model'
journalctl -k -b "$B" --no-pager | grep -m1 'Kernel command line' | sed 's/root=[^ ]*/root=…/'

sect "kernel log: USB controller, PHYs, enumeration"
journalctl -k -b "$B" --no-pager |
    grep -iE 'dwc3|xhci|a000000|88e0000|88e1000|eusb2|m31|qmp|usb[ -]|usb[0-9]|uas|scsi|sd[a-z]|regulator.*(dummy|supply)|phy' |
    grep -viE 'pcie|ufs|edp|dp[0-9]|mdss' | tail -150

if [ "$B" = 0 ]; then
    sect "drivers bound"
    for d in /sys/bus/platform/devices/a000000.usb /sys/bus/platform/devices/88e0000.phy /sys/bus/platform/devices/88e1000.phy; do
        printf '%s -> %s\n' "$d" "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null || echo none)"
    done
    lsmod | grep -E '^(dwc3|phy_qcom|xhci|usb_storage|uas|typec)'

    sect "USB topology and speeds"
    lsusb -t 2>&1
    for d in /sys/bus/usb/devices/*; do
        [ -f "$d/speed" ] || continue
        printf '%-12s speed=%-6s %s %s\n' "${d##*/}" "$(cat "$d/speed")" "$(cat "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)"
    done

    sect "block devices and mounts"
    lsblk -o NAME,SIZE,TRAN,LABEL,FSTYPE,MOUNTPOINTS 2>&1 | grep -vE '^loop'
fi
sync
echo; echo "Saved to $OUT"
