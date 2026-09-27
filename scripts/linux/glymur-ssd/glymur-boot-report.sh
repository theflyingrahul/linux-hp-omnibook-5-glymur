#!/usr/bin/env bash
set -u

# Per-boot bring-up report for the Glymur SSD install, run by
# glymur-boot-report.service 60 s after boot. It needs no login, so a boot
# with dead input still leaves evidence that the live USB can read from the
# SSD: /var/log/glymur/boot-<time>-<boot id>.txt (the newest 30 are kept).
# Read-only apart from the report itself.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
DIR=/var/log/glymur
mkdir -p "$DIR"
sleep "${GLYMUR_REPORT_DELAY:-60}"
boot_id="$(cut -c1-8 /proc/sys/kernel/random/boot_id)"
OUT="$DIR/boot-$(date +%Y%m%dT%H%M%S)-$boot_id.txt"

section() { printf '\n### %s\n' "$1"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1; }

{
    section 'kernel'
    uname -a
    cat /proc/cmdline
    uptime
    section 'ACPI overrides and _OSC'
    journalctl -k -b --no-pager | grep -E 'Table Upgrade|_OSC|cpuidle|acpi_idle' | head -20
    section 'bring-up drivers (ACPI ID -> driver)'
    for d in /sys/bus/platform/devices/QCOM0F0C:* /sys/bus/platform/devices/QCOM0F88:* \
        /sys/bus/platform/devices/QCOM0F10:* /sys/bus/platform/devices/ACPI0013:* \
        /sys/bus/platform/devices/ACPI000E:* /sys/bus/platform/devices/PNP0C0B:*; do
        [ -e "$d" ] || continue
        printf '%-28s %-18s %s\n' "$(basename "$d")" \
            "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)" \
            "$(cat "$d/firmware_node/path" 2>/dev/null)"
    done
    section 'module parameters'
    for p in /sys/module/glymur_acpi_gpio/parameters/* /sys/module/i2c_qcom_geni/parameters/*; do
        [ -r "$p" ] && printf '%s = %s\n' "$p" "$(cat "$p")"
    done
    section 'I2C adapters and clients'
    for a in /sys/bus/i2c/devices/*; do
        printf '%-14s %-24s %s\n' "$(basename "$a")" "$(cat "$a/name" 2>/dev/null)" \
            "$(basename "$(readlink "$a/driver" 2>/dev/null)" 2>/dev/null)"
    done
    section 'input devices'
    grep -E '^(N|H):' /proc/bus/input/devices
    section 'lid, fan, thermal'
    cat /proc/acpi/button/lid/*/state 2>/dev/null
    for f in /sys/bus/acpi/devices/PNP0C0B:*/physical_node*/fan_speed_rpm; do
        [ -r "$f" ] && printf 'fan_rpm %s\n' "$(cat "$f")"
    done
    for z in /sys/class/thermal/thermal_zone*; do
        printf '%s %s %s %s\n' "$(basename "$z")" "$(cat "$z/type" 2>/dev/null)" \
            "$(cat "$z/device/path" 2>/dev/null)" "$(cat "$z/temp" 2>/dev/null)"
    done
    section 'cpuidle'
    for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
        [ -d "$s" ] && printf '%s %s usage=%s\n' "$(basename "$s")" "$(cat "$s/name")" "$(cat "$s/usage")"
    done
    section 'network'
    run ip -br link
    run rfkill list
    run nmcli -t -f DEVICE,TYPE,STATE device
    section 'display'
    ls /sys/class/drm/ 2>&1
    section 'clock'
    run timedatectl show
    ls /sys/class/rtc/ 2>&1
    section 'failed units'
    systemctl --failed --no-legend --no-pager
    section 'kernel warnings and errors (this boot)'
    journalctl -k -b -p warning --no-pager | tail -150
    section 'oops check'
    journalctl -k -b --no-pager | grep -E 'Oops|BUG:|Call trace|WARNING: CPU' | head -20
} >"$OUT" 2>&1

ls -1t "$DIR"/boot-*.txt 2>/dev/null | tail -n +31 | xargs -r rm -f
