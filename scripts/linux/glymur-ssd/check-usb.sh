#!/usr/bin/env bash
set -u

# USB report for the "device tree (GPU and USB-A test)" boot. See README.md.
#   sudo bash check-usb.sh [--previous]

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
    grep -iE 'dwc3|xhci|a[0268]00000|88e[01]000|fd[35d]000|fde000|fa0000|eusb2|repeater|spmi|smb2370|m31|qmp|ucsi|typec|altmode|pmic_glink|role|usb[ -]|usb[0-9]|uas|scsi|sd[a-z]|uvc|video|regulator.*(dummy|supply)|phy' |
    grep -viE 'pcie|ufs|edp|mdss|apparmor=' | tail -200

# The filter above keeps only fragments of warnings; print them in full.
sect "kernel warnings and errors, in full"
journalctl -k -b "$B" --no-pager -o short-monotonic |
    awk '/-+\[ cut here \]-+|WARNING:|BUG:|Oops|kernfs: can not remove|Unable to handle/ { n = 45 }
         n > 0 { print; n-- }' | tail -400

if [ "$B" = 0 ]; then
    # From -8: SMB2370 PMICs on SPMI bus 2 (SIDs 9-11) with eUSB2 repeaters.
    sect "SPMI PMICs and eUSB2 repeaters"
    for d in /sys/bus/spmi/devices/*; do
        [ -e "$d" ] || { echo 'no SPMI devices (arbiter not bound?)'; break; }
        printf '%-14s driver=%s of_node=%s\n' "${d##*/}" \
            "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)" \
            "$(tr -d '\0' < "$d/of_node/name" 2>/dev/null)@$(od -An -tx4 -N4 --endian=big "$d/of_node/reg" 2>/dev/null | tr -d ' ')"
    done
    for d in /sys/bus/platform/devices/*eusb2* /sys/bus/platform/devices/*fd00*; do
        [ -e "$d" ] || continue
        printf '%s -> %s\n' "${d##*/}" "$( [ -e "$d/driver" ] && basename "$(readlink -f "$d/driver")" || echo 'not bound')"
    done
    journalctl -k -b 0 --no-pager | grep -iE 'repeater|parent PMIC|spmi|pmic@' | tail -30

    sect "drivers bound"
    for d in a000000.usb 88e0000.phy 88e1000.phy a600000.usb fd3000.phy fd5000.phy a800000.usb fdd000.phy fde000.phy a200000.usb fa0000.phy; do
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
        # A charger makes the port a sink and USB device, which is correct.
        pp="$p/$q-partner"
        [ -d "$pp" ] && printf '    partner: type=%s accessory=%s usb_pd=%s\n' \
            "$(cat "$pp/type" 2>/dev/null)" "$(cat "$pp/accessory_mode" 2>/dev/null)" \
            "$(cat "$pp/supports_usb_power_delivery" 2>/dev/null)"
    done
    for r in /sys/class/usb_role/*; do
        [ -e "$r/role" ] && printf '%s: role=%s\n' "${r##*/}" "$(cat "$r/role")"
    done

    sect "USB topology and speeds"
    lsusb -t 2>&1
    for d in /sys/bus/usb/devices/*; do
        [ -f "$d/speed" ] || continue
        # a000000 USB-A, a600000 USB-C hinge, a800000 USB-C, a200000 camera.
        c="$(readlink -f "$d" | grep -oE 'a[0268]00000\.usb' | head -1)"
        printf '%-12s %-14s speed=%-6s %s %s\n' "${d##*/}" "${c:-?}" "$(cat "$d/speed")" "$(cat "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)"
    done

    sect "camera (usb_hs, from kernel -8)"
    lsusb -d 30c9: 2>&1 || echo 'no 30c9: device (the HP camera) on USB'
    for v in /sys/class/video4linux/video*; do
        [ -e "$v" ] && printf '%s: %s\n' "${v##*/}" "$(cat "$v/name" 2>/dev/null)"
    done

    sect "block devices and mounts"
    lsblk -o NAME,SIZE,TRAN,LABEL,FSTYPE,MOUNTPOINTS 2>&1 | grep -vE '^loop'
fi
sync
echo; echo "Saved to $OUT"
