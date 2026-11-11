#!/usr/bin/env bash
set -u

# USB report for the device-tree boots with USB. See README.md.
#   sudo bash check-usb.sh [--previous]
#   sudo bash check-usb.sh --ss-stress [cycles]   (USB-A SuperSpeed, from -23)

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
B=0
STRESS=0
[ "${1:-}" = --previous ] && B=-1
if [ "${1:-}" = --ss-stress ]; then STRESS=1; CYCLES="${2:-20}"; fi
OUT="/var/log/glymur/usb-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
# Personal identifiers stay out of the log (it may end up in the
# repository): MAC and Bluetooth addresses, UUIDs, USB serial numbers,
# the camera's serial-like manufacturer string, user names in paths.
redact() {
    sed -u -E -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
        -e 's/\b[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b/<uuid>/g' \
        -e 's/(SerialNumber: ).*/\1<serial>/' \
        -e 's/(Manufacturer: )[A-Z0-9]{12,}$/\1<id>/' \
        -e 's#(/home/|/media/)[^/ ]+#\1user#g'
}
exec > >(redact | tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

# --ss-stress: the USB-A port's SuperSpeed link (a000000.usb, usb_2_qmpphy),
# which failed on 2 of ~15 boots. Run it on the test device tree (HP's PHYC
# values) and on the daily one (Linux's), with the same stick, and compare.
# Only reads the stick: unmounts its partitions, reads 1 GiB, then resets
# the device and re-trains the link. docs/usb-a-superspeed-2026-11-11.md
if [ "$STRESS" = 1 ]; then
    sect "USB-A SuperSpeed stress, $CYCLES cycles"
    uname -r
    tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
    ov=$(find /sys/firmware/devicetree/base -path '*phy@88e1000/qcom,usb3-lane-a-overrides' 2>/dev/null | head -1)
    echo "HP PHYC overrides in this device tree: $( [ -n "$ov" ] && od -An -tx4 --endian=big "$ov" | xargs || echo none)"
    journalctl -k -b --no-pager | grep 'USB3 lane A' | head -4
    ss=""; hs=""
    for u in /sys/bus/usb/devices/usb*; do
        readlink -f "$u" | grep -q 'a000000\.usb' || continue
        case "$(cat "$u/speed")" in 480) hs=${u##*/usb} ;; *) ss=${u##*/usb} ;; esac
    done
    echo "USB-A buses: SuperSpeed $ss, high speed $hs"
    [ -n "$ss" ] || { echo 'no USB-A SuperSpeed bus; nothing to test'; exit 1; }
    errs() {
        journalctl -k --no-pager --since "@$1" |
            grep -cE "usb ($ss|$hs)-1: (device not accepting address|Device not responding to setup address|device descriptor read|reset SuperSpeed)|usb usb$ss-port1: (Cannot enable|attempt power cycle|unable to enumerate)"
    }
    where() {
        if [ -e "/sys/bus/usb/devices/$ss-1" ]; then echo "SS $(cat "/sys/bus/usb/devices/$ss-1/speed")"
        elif [ -e "/sys/bus/usb/devices/$hs-1" ]; then echo "HS $(cat "/sys/bus/usb/devices/$hs-1/speed")"
        else echo none; fi
    }
    blk() {
        local d
        d=$(ls -d /sys/bus/usb/devices/"$ss"-1/*/host*/target*/*/block/* \
                  /sys/bus/usb/devices/"$hs"-1/*/host*/target*/*/block/* 2>/dev/null | head -1)
        echo "${d##*/}"
    }
    echo "this boot so far: $(errs "$(date -d "$(uptime -s)" +%s)") link errors; stick now: $(where)"
    dev=$(blk)
    [ -n "$dev" ] || { echo 'no block device on the USB-A port'; exit 1; }
    echo "block device: /dev/$dev ($(lsblk -dno SIZE,MODEL "/dev/$dev" | xargs))"
    mnt=$(lsblk -nro MOUNTPOINTS "/dev/$dev" | grep -v '^$')
    if [ -n "$mnt" ]; then
        echo "mounted: $(echo $mnt)"
        echo 'Unmount them for the test (the stick is only read)? [y/N]'
        read -r a </dev/tty
        [ "$a" = y ] || { echo 'not unmounted; stopping'; exit 1; }
        for p in $(lsblk -nro NAME "/dev/$dev"); do
            if lsblk -nro MOUNTPOINTS "/dev/$p" | grep -q .; then
                umount "/dev/$p" && echo "unmounted /dev/$p"
            fi
        done
    fi
    t0=$(date +%s)
    echo "-- read 1 GiB (O_DIRECT)"
    dd if="/dev/$dev" of=/dev/null bs=1M count=1024 iflag=direct 2>&1 | tail -1
    echo "link errors during the read: $(errs "$t0"); stick: $(where)"
    reset_dev() {
        python3 - "$1" <<'PY'
import fcntl, os, sys
fd = os.open(sys.argv[1], os.O_WRONLY)
try:
    fcntl.ioctl(fd, 0x5514)   # USBDEVFS_RESET
    print("ok")
except OSError as e:
    print("failed:", e)
PY
    }
    ok_ss=0; ok_hs=0; gone=0
    for i in $(seq 1 "$CYCLES"); do
        t=$(date +%s)
        u="/sys/bus/usb/devices/$ss-1"; [ -e "$u" ] || u="/sys/bus/usb/devices/$hs-1"
        if [ $((i % 2)) = 1 ] && [ -e "$u" ]; then
            how="device reset $(reset_dev "/dev/bus/usb/$(printf %03d "$(cat "$u/busnum")")/$(printf %03d "$(cat "$u/devnum")")")"
        else
            echo 1 > "/sys/bus/usb/devices/$ss-0:1.0/usb$ss-port1/disable"; sleep 1
            echo 0 > "/sys/bus/usb/devices/$ss-0:1.0/usb$ss-port1/disable"
            how="port disable/enable"
        fi
        for _ in $(seq 1 20); do sleep 0.5; [ "$(where)" != none ] && break; done
        sleep 1; w=$(where)
        r=""
        if [ "$w" != none ]; then
            d=""
            for _ in $(seq 1 10); do d=$(blk); [ -n "$d" ] && break; sleep 0.5; done
            [ -n "$d" ] && r=$(dd if="/dev/$d" of=/dev/null bs=1M count=64 iflag=direct 2>&1 | tail -1 | sed 's/.*copied, //')
        fi
        case "$w" in SS*) ok_ss=$((ok_ss + 1)) ;; HS*) ok_hs=$((ok_hs + 1)) ;; *) gone=$((gone + 1)) ;; esac
        printf '%2d %-24s -> %-9s errors=%s %s\n' "$i" "$how" "$w" "$(errs "$t")" "$r"
    done
    echo "-- summary: back at SuperSpeed $ok_ss, at high speed $ok_hs, gone $gone of $CYCLES; link errors in all: $(errs "$t0")"
    [ "$gone" -gt 0 ] && echo 'The stick is gone: unplug it and plug it back in.'
    journalctl -k --no-pager --since "@$t0" |
        grep -E "usb ($ss|$hs)-1|usb$ss-port1|usb$hs-port1|a000000|qmp" | tail -60
    sync; echo; echo "Saved to $OUT"
    exit 0
fi

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
        printf '%-12s %-14s speed=%-6s %s %s\n' "${d##*/}" "${c:-?}" "$(cat "$d/speed")" "$(sed -E 's/^[A-Z0-9]{12,}$/<id>/' "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)"
    done

    sect "camera (usb_hs, from kernel -8)"
    lsusb -d 30c9: 2>&1 || echo 'no 30c9: device (the HP camera) on USB'
    for v in /sys/class/video4linux/video*; do
        [ -e "$v" ] && printf '%s: %s\n' "${v##*/}" "$(cat "$v/name" 2>/dev/null)"
    done

    sect "block devices and mounts"
    lsblk -o NAME,SIZE,TRAN,FSTYPE,MOUNTPOINTS 2>&1 | grep -vE '^loop'
fi
sync
echo; echo "Saved to $OUT"
