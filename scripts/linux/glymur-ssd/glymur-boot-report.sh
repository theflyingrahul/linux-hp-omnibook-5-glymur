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
    if [ -r /proc/device-tree/model ]; then
        section 'device tree: machine'
        printf 'model: %s\n' "$(tr -d '\0' </proc/device-tree/model)"
        printf 'compatible: %s\n' "$(tr '\0' ' ' </proc/device-tree/compatible)"
        # SMEM socinfo (not the serial number, which stays private).
        for f in machine family soc_id revision; do
            [ -r "/sys/devices/soc0/$f" ] && printf 'soc0 %s: %s\n' "$f" "$(cat "/sys/devices/soc0/$f")"
        done
        printf 'cpus online: %s\n' "$(cat /sys/devices/system/cpu/online)"
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            [ -d "$p" ] && printf '%s %s cur=%s max=%s\n' "$(basename "$p")" \
                "$(cat "$p/scaling_driver" 2>/dev/null)" "$(cat "$p/scaling_cur_freq" 2>/dev/null)" \
                "$(cat "$p/cpuinfo_max_freq" 2>/dev/null)"
        done
        section 'device tree: deferred probes and pending sync_state'
        cat /sys/kernel/debug/devices_deferred 2>&1
        journalctl -k -b --no-pager | grep -E 'sync_state\(\) pending|deferred probe pending' | head -40
        section 'device tree: storage and PCIe'
        run lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
        run lspci -nnk
        section 'device tree: remoteprocs'
        for r in /sys/class/remoteproc/remoteproc*; do
            [ -d "$r" ] && printf '%s %s %s %s\n' "$(basename "$r")" "$(cat "$r/name" 2>/dev/null)" \
                "$(cat "$r/state" 2>/dev/null)" "$(cat "$r/firmware" 2>/dev/null)"
        done
        section 'device tree: power supplies, USB-C, RTC'
        for s in /sys/class/power_supply/*; do
            [ -d "$s" ] && printf '%s type=%s status=%s capacity=%s online=%s\n' "$(basename "$s")" \
                "$(cat "$s/type" 2>/dev/null)" "$(cat "$s/status" 2>/dev/null)" \
                "$(cat "$s/capacity" 2>/dev/null)" "$(cat "$s/online" 2>/dev/null)"
        done
        ls /sys/class/typec/ 2>&1
        section 'device tree: display connectors'
        for c in /sys/class/drm/card*-*; do
            [ -d "$c" ] && printf '%s status=%s enabled=%s mode=%s\n' "$(basename "$c")" \
                "$(cat "$c/status" 2>/dev/null)" "$(cat "$c/enabled" 2>/dev/null)" \
                "$(head -n 1 "$c/modes" 2>/dev/null)"
        done
        cat /sys/class/backlight/*/brightness 2>/dev/null
        section 'device tree: bluetooth'
        ls /sys/class/bluetooth/ 2>&1
        journalctl -k -b --no-pager | grep -iE 'bluetooth|hci_uart|qca' | head -30
        section 'device tree: power domains (genpd)'
        head -n 120 /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>&1
        section 'device tree: SoC driver messages'
        journalctl -k -b --no-pager | grep -iE 'qcom|pcie|nvme|remoteproc|pmic_glink|msm|dpu|edp|panel|geni|i2c_hid|dispcc|rpmh|interconnect|tsens|pinctrl|gpio|smmu|ath12k|soccp|adsp|cdsp|battmgr|ucsi' | head -300
    fi
    section 'failed units'
    systemctl --failed --no-legend --no-pager
    section 'kernel warnings and errors (this boot)'
    journalctl -k -b -p warning --no-pager | tail -150
    section 'oops check'
    journalctl -k -b --no-pager | grep -E 'Oops|BUG:|Call trace|WARNING: CPU' | head -20
} >"$OUT" 2>&1

ls -1t "$DIR"/boot-*.txt 2>/dev/null | tail -n +31 | xargs -r rm -f
