#!/usr/bin/env bash
set -u

# USB check for the "device tree (GPU and USB-A test)" boot: the right-hand
# USB-A port (usb_2) and the two left-hand USB-C ports (usb_0 next to the
# hinge, usb_1 away from it), written to /var/log/glymur/usb-test-<time>.txt.
# If the USB-A port works it can be run straight from the USB stick:
#
#   sudo bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/check-usb.sh"
#
# Before running it, plug in what you have: a USB 2.0 device (mouse,
# keyboard receiver) in the USB-A port next to or instead of the stick, and
# a USB-C device (stick, hub, phone) in each USB-C port.
#
# If the USB-A port does not work, boot any other entry afterwards and run
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

sect "kernel log: USB controllers, PHYs, Type-C, enumeration"
journalctl -k -b "$B" --no-pager |
    grep -iE 'dwc3|xhci|a[068]00000|88e[01]000|fd[35d]000|fde000|eusb2|m31|qmp|ucsi|typec|altmode|pmic_glink|role|usb[ -]|usb[0-9]|uas|scsi|sd[a-z]|regulator.*(dummy|supply)|phy' |
    grep -viE 'pcie|ufs|edp|mdss' | tail -200

if [ "$B" = 0 ]; then
    sect "drivers bound"
    for d in a000000.usb 88e0000.phy 88e1000.phy a600000.usb fd3000.phy fd5000.phy a800000.usb fdd000.phy fde000.phy; do
        p="/sys/bus/platform/devices/$d"
        printf '%-14s -> %s\n' "$d" "$( [ -e "$p/driver" ] && basename "$(readlink -f "$p/driver")" || echo none)"
    done
    lsmod | grep -E '^(dwc3|phy_qcom|xhci|usb_storage|uas|typec|ucsi|pmic_glink)'

    sect "USB-C: ports, partners, data roles"
    for p in /sys/class/typec/port?; do
        q="${p##*/}"
        printf '%s: data_role=%s power_role=%s opmode=%s orientation=%s partner=%s\n' "$q" \
            "$(cat "$p/data_role")" "$(cat "$p/power_role")" "$(cat "$p/power_operation_mode")" \
            "$(cat "$p/orientation" 2>/dev/null)" "$([ -d "$p/$q-partner" ] && echo yes || echo no)"
    done
    for r in /sys/class/usb_role/*; do
        [ -e "$r/role" ] && printf '%s: role=%s\n' "${r##*/}" "$(cat "$r/role")"
    done

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
