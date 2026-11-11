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
# Personal identifiers stay out of the report (it may end up in the
# repository): MAC and Bluetooth addresses, UUIDs, USB serial numbers,
# the camera's serial-like manufacturer string, user names in paths.
redact() {
    sed -u -E -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
        -e 's/\b[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b/<uuid>/g' \
        -e 's/(SerialNumber: ).*/\1<serial>/' \
        -e 's/(Manufacturer: )[A-Z0-9]{12,}$/\1<id>/' \
        -e 's#(/home/|/media/)[^/ ]+#\1user#g'
}

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
    # With PSCI OS-initiated idle, cluster and system idle are genpd states.
    journalctl -k -b --no-pager | grep -E 'CPUidle PSCI|psci: (OSI|PSCI)' | head -3
    for d in power-domain-cpu-cluster0 power-domain-cpu-cluster1 power-domain-system; do
        [ -d "/sys/kernel/debug/pm_genpd/$d" ] || continue
        printf '%s:\n' "$d"
        sed 's/^/  /' "/sys/kernel/debug/pm_genpd/$d/idle_states" 2>&1
        printf '  active %s ms, idle %s ms\n' \
            "$(cat "/sys/kernel/debug/pm_genpd/$d/active_time" 2>/dev/null)" \
            "$(cat "/sys/kernel/debug/pm_genpd/$d/total_idle_time" 2>/dev/null)"
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
        run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
        run lspci -nnk
        # From -23: the boot stick's SuperSpeed link, once per boot (it
        # failed on 2 of ~15 boots; docs/usb-a-superspeed-2026-11-11.md).
        section 'device tree: USB-A (a000000.usb) link'
        ov=$(find /sys/firmware/devicetree/base -path '*phy@88e1000/qcom,usb3-lane-a-overrides' 2>/dev/null | head -1)
        printf 'HP PHYC overrides in the device tree: %s\n' "$( [ -n "$ov" ] && od -An -tx4 --endian=big "$ov" | xargs || echo none)"
        journalctl -k -b --no-pager | grep 'USB3 lane A' | head -4
        buses=""
        for u in /sys/bus/usb/devices/usb*; do
            readlink -f "$u" | grep -q 'a000000\.usb' && buses="$buses ${u##*/usb}"
        done
        for b in $buses; do
            printf 'bus %s (%s Mb/s root): device %s\n' "$b" "$(cat /sys/bus/usb/devices/usb$b/speed 2>/dev/null)" \
                "$( [ -e /sys/bus/usb/devices/$b-1 ] && echo "$b-1 at $(cat /sys/bus/usb/devices/$b-1/speed) Mb/s" || echo none)"
            printf '  errors: %s\n' "$(journalctl -k -b --no-pager | grep -cE "usb $b-1: (device not accepting address|Device not responding to setup address|device descriptor read)|usb usb$b-port1: (Cannot enable|attempt power cycle|unable to enumerate)")"
        done
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
        section 'device tree: QUP serial-engine clocks (DFS level in use)'
        for c in /sys/kernel/debug/clk/gcc_qupv3_wrap*_s*_clk; do
            [ -r "$c/clk_enable_count" ] || continue
            printf '%s rate=%s enable=%s prepare=%s\n' "$(basename "$c")" "$(cat "$c/clk_rate")" \
                "$(cat "$c/clk_enable_count")" "$(cat "$c/clk_prepare_count")"
        done
        journalctl -k -b --no-pager | grep -E 'I2C clk selected|Unsupported SE source clock' | head -20
        section 'device tree: SoC driver messages'
        journalctl -k -b --no-pager | grep -iE 'qcom|pcie|nvme|remoteproc|pmic_glink|msm|dpu|edp|panel|geni|i2c_hid|dispcc|rpmh|interconnect|tsens|pinctrl|gpio|smmu|ath12k|soccp|adsp|cdsp|battmgr|ucsi' | head -300
    fi
    section 'failed units'
    systemctl --failed --no-legend --no-pager
    section 'kernel warnings and errors (this boot)'
    journalctl -k -b -p warning --no-pager | tail -150
    section 'oops check'
    journalctl -k -b --no-pager | grep -E 'Oops|BUG:|Call trace|WARNING: CPU' | head -20
} 2>&1 | redact >"$OUT"

ls -1t "$DIR"/boot-*.txt 2>/dev/null | tail -n +31 | xargs -r rm -f
