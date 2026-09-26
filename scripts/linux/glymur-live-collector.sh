#!/usr/bin/env bash

# Collect Linux-native bring-up evidence without requiring keyboard, touchpad,
# mouse, network, or an interactive desktop. Intended for systemd.run=.

set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf 'unknown')"
OUTPUT=""
PROGRESS=""

choose_output() {
    local base
    for base in /cdrom/glymur-logs /var/log/glymur-live /tmp/glymur-live; do
        if mkdir -p "$base" 2>/dev/null && touch "$base/.write-test" 2>/dev/null; then
            rm -f "$base/.write-test"
            if OUTPUT="$(mktemp -d "$base/$RUN_ID.XXXXXX" 2>/dev/null)"; then
                PROGRESS="$OUTPUT/progress.log"
                return 0
            fi
        fi
    done
    return 1
}

capture_cmd() {
    local name="$1"
    local status
    shift
    printf '%s start %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$name" >>"$PROGRESS"
    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=5s 30s "$@" >"$OUTPUT/$name" 2>&1
        status=$?
    else
        "$@" >"$OUTPUT/$name" 2>&1
        status=$?
    fi
    printf '%s finish %s status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$name" "$status" >>"$PROGRESS"
    if [ "$status" -ne 0 ]; then
        printf 'command status: %s\n' "$status" >>"$OUTPUT/$name"
    fi
    return 0
}

capture_shell() {
    local name="$1"
    local status
    shift
    printf '%s start %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$name" >>"$PROGRESS"
    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=5s 30s bash -c "$*" >"$OUTPUT/$name" 2>&1
        status=$?
    else
        bash -c "$*" >"$OUTPUT/$name" 2>&1
        status=$?
    fi
    printf '%s finish %s status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$name" "$status" >>"$PROGRESS"
    if [ "$status" -ne 0 ]; then
        printf '\ncommand status: %s\n' "$status" >>"$OUTPUT/$name"
    fi
    return 0
}

wait_for_media() {
    local attempt
    for attempt in $(seq 1 60); do
        if [ -d /cdrom/casper ] || mountpoint -q /cdrom 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 0
}

remount_media_rw() {
    local fstype
    fstype="$(findmnt -no FSTYPE /cdrom 2>/dev/null || true)"
    case "$fstype" in
        vfat|msdos|exfat)
            mount -o remount,rw /cdrom 2>/dev/null || true
            ;;
    esac
}

wait_for_media
remount_media_rw

if ! choose_output; then
    exit 1
fi

{
    printf 'collector_version=2\n'
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    printf 'output=%s\n' "$OUTPUT"
} >"$OUTPUT/collector-info.txt"

capture_cmd uname.txt uname -a
capture_cmd os-release.txt cat /etc/os-release
capture_cmd cmdline.txt cat /proc/cmdline
capture_cmd dmesg.txt dmesg
capture_shell journal-kernel.txt 'journalctl --no-pager -b -k'
capture_cmd mounts.txt mount
capture_cmd findmnt.txt findmnt -R
capture_cmd lsblk.txt lsblk -o NAME,PATH,TYPE,FSTYPE,LABEL,UUID,SIZE,RO,MOUNTPOINTS
capture_cmd blkid.txt blkid
capture_cmd lspci.txt lspci -nnvv
capture_cmd lsusb.txt lsusb -tv
capture_shell acpi-tables.txt 'find /sys/firmware/acpi/tables -maxdepth 1 -type f -printf "%f\\n" 2>/dev/null | sort'
capture_shell i2c-devices.txt 'find /sys/bus/i2c/devices -maxdepth 1 -mindepth 1 -printf "%f\\n" 2>/dev/null | sort'
capture_shell acpi-devices.txt 'for d in /sys/bus/acpi/devices/*; do [ -d "$d" ] || continue; printf "### %s\\n" "$d"; for f in hid modalias path status; do [ -r "$d/$f" ] && { printf "%s=" "$f"; cat "$d/$f"; }; done; if [ -L "$d/driver" ]; then printf "driver=%s\\n" "$(readlink -f "$d/driver")"; else printf "driver=UNBOUND\\n"; fi; if [ -L "$d/physical_node" ]; then printf "physical_node=%s\\n" "$(readlink -f "$d/physical_node")"; fi; done'
capture_shell platform-devices.txt 'for d in /sys/bus/platform/devices/*; do [ -d "$d" ] || continue; printf "### %s\\n" "$d"; cat "$d/uevent" 2>/dev/null || true; if [ -L "$d/driver" ]; then printf "driver=%s\\n" "$(readlink -f "$d/driver")"; else printf "driver=UNBOUND\\n"; fi; done'
capture_shell kernel-config-i2c.txt 'if [ -r /proc/config.gz ]; then zcat /proc/config.gz; elif [ -r "/boot/config-$(uname -r)" ]; then cat "/boot/config-$(uname -r)"; else printf "kernel configuration unavailable\\n"; fi | grep -E "^(CONFIG_ACPI=|CONFIG_I2C=|CONFIG_I2C_QCOM_GENI=|CONFIG_QCOM_GENI_SE=|# CONFIG_I2C_QCOM_GENI is not set|kernel configuration unavailable)"'
capture_cmd lsmod.txt lsmod
capture_shell usb-devices.txt 'find /sys/bus/usb/devices -maxdepth 1 -mindepth 1 -printf "%f\\n" 2>/dev/null | sort'
capture_shell typec-devices.txt 'for d in /sys/class/typec/*; do [ -e "$d" ] || continue; printf "### %s\\n" "$d"; for f in data_role power_role port_type preferred_role orientation; do [ -r "$d/$f" ] && { printf "%s=" "$f"; cat "$d/$f"; }; done; if [ -L "$d/device" ]; then printf "device=%s\\n" "$(readlink -f "$d/device")"; fi; done'
capture_shell input-devices.txt 'find /sys/class/input -maxdepth 1 -mindepth 1 -printf "%f\\n" 2>/dev/null | sort'
capture_shell pci-devices.txt 'find /sys/bus/pci/devices -maxdepth 1 -mindepth 1 -printf "%f\\n" 2>/dev/null | sort'
capture_cmd input-proc.txt cat /proc/bus/input/devices
capture_cmd interrupts.txt cat /proc/interrupts
capture_cmd efibootmgr.txt efibootmgr -v
capture_cmd secure-boot.txt mokutil --sb-state
capture_cmd dmi.txt dmidecode
capture_shell i2c-uevents.txt 'for d in /sys/bus/i2c/devices/*; do [ -d "$d" ] || continue; printf "### %s\\n" "$d"; cat "$d/uevent" 2>/dev/null || true; if [ -L "$d/driver" ]; then printf "driver=%s\\n" "$(readlink -f "$d/driver")"; else printf "driver=UNBOUND\\n"; fi; done'
capture_shell usb-uevents.txt 'for d in /sys/bus/usb/devices/*; do [ -d "$d" ] || continue; printf "### %s\\n" "$d"; cat "$d/uevent" 2>/dev/null || true; if [ -L "$d/driver" ]; then printf "driver=%s\\n" "$(readlink -f "$d/driver")"; else printf "driver=UNBOUND\\n"; fi; done'
capture_shell input-sysfs.txt 'for d in /sys/class/input/*; do [ -e "$d" ] || continue; printf "### %s\\n" "$d"; udevadm info --query=all --path="${d#/sys}" 2>/dev/null || true; done'

if [ -d /sys/firmware/acpi/tables ]; then
    tar -C /sys/firmware -czf "$OUTPUT/acpi-tables.tar.gz" acpi/tables 2>"$OUTPUT/acpi-tables-tar-errors.txt" || true
fi

printf 'completed_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" >>"$OUTPUT/collector-info.txt"
touch "$OUTPUT/COMPLETE" 2>/dev/null || true
sync

# If /cdrom was writable, OUTPUT is already on the installer. Otherwise try to
# export the persistent-overlay copy back to the installer before shutdown.
if [[ "$OUTPUT" != /cdrom/* ]]; then
    mkdir -p /cdrom/glymur-logs 2>/dev/null || true
    tar -C "$(dirname "$OUTPUT")" -czf \
        "/cdrom/glymur-logs/glymur-live-$RUN_ID.tar.gz" \
        "$(basename "$OUTPUT")" 2>"$OUTPUT/export-errors.txt" || true
fi

sync
exit 0
