#!/usr/bin/env bash

# Default-off hardware inventory on the Ubuntu ARM64 live image.
# Capture in RAM, save only to the serial-verified installer FAT volume, and
# make one verified upstream Wi-Fi firmware retry without touching internal storage.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

EXPECTED_UUID=1F0F-186A  # Rufus re-image 2026-09-26 (was 07F8-1419)
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf unknown)"
WORK="$(mktemp -d /run/glymur-system-inventory.XXXXXX)" || exit 1
DATA="$WORK/data"
mkdir -p "$DATA" "$WORK/media" || exit 1
MEDIA_SERIAL=""
OUTPUT_NAME=""
MOUNTED=0
PORT_MONITOR_PID=""
PROGRESS_TTY=/dev/tty6

show_progress() {
    if command -v chvt >/dev/null 2>&1; then
        chvt 6 >/dev/null 2>&1 || true
        if [ -w "$PROGRESS_TTY" ]; then
            {
                printf '\033[H\033[2J'
                printf 'GLYMUR WHOLE-SYSTEM INVENTORY\n\n'
                printf 'No keyboard input is required. Do not remove the installer USB.\n'
                printf 'The graphical desktop runs in the background during this test.\n'
                printf 'The machine powers off after the collector finishes.\n\n'
                tail -n 10 "$DATA/progress.log" 2>/dev/null || true
            } >"$PROGRESS_TTY" 2>/dev/null || true
        fi
    fi
}

say() {
    printf '%s\n' "$*" | tee -a "$DATA/progress.log" >/dev/console
    show_progress
}

wait_visible() {
    local seconds="$1" label="$2" step remaining
    while [ "$seconds" -gt 0 ]; do
        say "$label: $seconds seconds remaining."
        step=10
        if [ "$seconds" -lt "$step" ]; then
            step="$seconds"
        fi
        sleep "$step"
        seconds=$((seconds - step))
    done
}

cleanup() {
    if [ -n "$PORT_MONITOR_PID" ]; then
        kill "$PORT_MONITOR_PID" 2>/dev/null || true
        wait "$PORT_MONITOR_PID" 2>/dev/null || true
    fi
    if [ "$MOUNTED" -eq 1 ]; then
        sync
        umount "$WORK/media" 2>/dev/null || true
    fi
}
trap cleanup EXIT

stop_now() {
    say "$*"
    say 'This collector did not request an internal-disk mount. Power-off follows in 30 seconds.'
    wait_visible 30 'Safety stop'
    exit 1
}

media_device() {
    local dev disk serial
    dev="$(timeout 5s blkid -U "$EXPECTED_UUID" 2>/dev/null || true)"
    [ -n "$dev" ] && [ -b "$dev" ] || return 1
    [ "$(blkid -s TYPE -o value "$dev" 2>/dev/null)" = vfat ] || return 1
    disk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n 1)"
    [ -n "$disk" ] && [ -b "/dev/$disk" ] || return 1
    serial="$(udevadm info -q property -n "/dev/$disk" 2>/dev/null |
        sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1)"
    [ -n "$serial" ] && [ "$serial" = "$MEDIA_SERIAL" ] || return 1
    printf '%s\n' "$dev"
}

capture() {
    local name="$1" status
    shift
    say "Capturing $name (up to 20 seconds)."
    timeout --kill-after=3s 20s "$@" >"$DATA/$name.txt" 2>&1
    status=$?
    printf '%s status=%s\n' "$name" "$status" >>"$DATA/commands.log"
    say "Finished $name (status $status)."
    return 0
}

capture_class() {
    local name="$1" path="$2" attrs="$3" node attr count=0
    say "Capturing $name devices."
    {
        for node in "$path"/*; do
            [ -e "$node" ] || continue
            count=$((count + 1))
            if [ $((count % 10)) -eq 0 ]; then
                say "Capturing $name: $count devices checked."
            fi
            printf '### %s\n' "$node"
            printf 'realpath=%s\n' "$(readlink -f "$node" 2>/dev/null || true)"
            if [ -L "$node/driver" ]; then
                printf 'driver=%s\n' "$(readlink -f "$node/driver")"
            else
                printf 'driver=UNBOUND_OR_NOT_APPLICABLE\n'
            fi
            if [ -L "$node/device/driver" ]; then
                printf 'device_driver=%s\n' "$(readlink -f "$node/device/driver")"
            fi
            for attr in $attrs; do
                if [ -r "$node/$attr" ]; then
                    printf '%s=' "$attr"
                    timeout --kill-after=1s 2s cat "$node/$attr" 2>&1 || true
                    printf '\n'
                fi
            done
        done
    } >"$DATA/$name.txt" 2>&1
    say "Finished $name: $count devices checked."
}

save_logs() {
    local phase="$1" dev dest media_root existing_mount copied=0 own_mount=0
    say "Saving $phase checkpoint to the installer USB."
    if ! dev="$(media_device)"; then
        say "SAVE FAILED ($phase): installer identity or FAT partition changed."
        return 1
    fi
    existing_mount="$(findmnt -rn -S "$dev" -o TARGET 2>/dev/null || true)"
    if [ -n "$existing_mount" ]; then
        if [ "$(printf '%s\n' "$existing_mount" | wc -l)" -ne 1 ] ||
            [ "$(findmnt -rn -T "$existing_mount" -o FSTYPE 2>/dev/null)" != vfat ] ||
            ! findmnt -rn -T "$existing_mount" -o OPTIONS | grep -Eq '(^|,)rw(,|$)'; then
            say "SAVE FAILED ($phase): installer is mounted ambiguously or read-only."
            return 1
        fi
        media_root="$existing_mount"
    else
        if ! timeout --kill-after=3s 20s mount -t vfat -o rw,nosuid,nodev,noexec \
            "$dev" "$WORK/media"; then
            say "SAVE FAILED ($phase): installer FAT mount failed."
            return 1
        fi
        media_root="$WORK/media"
        own_mount=1
        MOUNTED=1
    fi
    if ! mkdir -p "$media_root/glymur-logs"; then
        say "SAVE FAILED ($phase): cannot create the log directory."
    else
        if [ -z "$OUTPUT_NAME" ]; then
            dest="$(mktemp -d "$media_root/glymur-logs/system-inventory-$RUN_ID.XXXXXX")" || true
            if [ -n "${dest:-}" ]; then
                OUTPUT_NAME="$(basename "$dest")"
            fi
        fi
        if [ -n "$OUTPUT_NAME" ]; then
            dest="$media_root/glymur-logs/$OUTPUT_NAME"
            if timeout --kill-after=5s 40s cp -R "$DATA/." "$dest/" &&
                touch "$dest/$phase"; then
                copied=1
            else
                say "SAVE FAILED ($phase): partial logs may remain in $OUTPUT_NAME."
            fi
        else
            say "SAVE FAILED ($phase): cannot allocate the log directory."
        fi
    fi
    sync
    if [ "$own_mount" -eq 1 ]; then
        if ! umount "$WORK/media"; then
            say "SAVE WARNING ($phase): installer partition did not unmount cleanly."
            return 1
        fi
        MOUNTED=0
    fi
    if [ "$copied" -eq 1 ]; then
        say "Saved $phase under glymur-logs/$OUTPUT_NAME"
        return 0
    fi
    return 1
}

say "Glymur whole-system inventory: $RUN_ID"
say 'The only optional action is connecting a USB-C device during the two port windows.'
if ! grep -qw toram /proc/cmdline || ! grep -qw nopersistent /proc/cmdline; then
    stop_now 'STOP: toram nopersistent is required.'
fi
if [ "$(findmnt -no FSTYPE /cdrom 2>/dev/null || true)" != tmpfs ]; then
    stop_now 'STOP: /cdrom is not RAM-backed; do not remove or alter the installer.'
fi
if ! command -v timeout >/dev/null || ! command -v systemctl >/dev/null; then
    stop_now 'STOP: required live-system tools are missing.'
fi
INITIAL_DEV="$(timeout 5s blkid -U "$EXPECTED_UUID" 2>/dev/null || true)"
INITIAL_DISK="$(lsblk -no PKNAME "$INITIAL_DEV" 2>/dev/null | head -n 1)"
if [ -z "$INITIAL_DEV" ] || [ -z "$INITIAL_DISK" ] ||
    [ ! -b "/dev/$INITIAL_DISK" ]; then
    stop_now 'STOP: expected installer disk is absent.'
fi
MEDIA_SERIAL="$(udevadm info -q property -n "/dev/$INITIAL_DISK" 2>/dev/null |
    sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1)"
if [ -z "$MEDIA_SERIAL" ] || ! media_device >/dev/null; then
    stop_now 'STOP: installer FAT UUID, type, or serial did not verify.'
fi
if lsblk -nr -o MOUNTPOINTS "/dev/$INITIAL_DISK" | grep -q '[^[:space:]]'; then
    stop_now 'STOP: installer is still mounted after RAM boot.'
fi

printf 'run_id=%s\ncollector_version=1\n' "$RUN_ID" >"$DATA/collector-info.txt"
printf 'installer_uuid=%s\ninstaller_serial=%s\n' "$EXPECTED_UUID" "$MEDIA_SERIAL" \
    >>"$DATA/collector-info.txt"
capture early-uname uname -a
capture early-cmdline cat /proc/cmdline
capture early-os-release cat /etc/os-release
capture early-dmesg dmesg
capture early-lsmod lsmod
capture early-drm bash -c 'ls -la /dev/dri /sys/class/drm 2>&1'
capture early-net bash -c 'ls -la /sys/class/net /sys/class/bluetooth 2>&1'
capture early-input cat /proc/bus/input/devices
capture early-lsusb lsusb -t
capture early-lspci lspci -nnk
capture early-systemd-failed systemctl --failed --no-pager --plain
if ! save_logs EARLY && [ "$MOUNTED" -eq 1 ]; then
    stop_now 'STOP: installer FAT remains mounted after the early save attempt.'
fi

udevadm monitor --kernel --udev >"$DATA/port-events.txt" 2>&1 &
PORT_MONITOR_PID=$!
say 'Optional USB-C test: connect a known-working USB-C device to the left'
say 'port NEAREST THE DISPLAY HINGE for 30 seconds. Keep installer in USB-A.'
say 'Do not unplug the charger or use a port already occupied by it.'
wait_visible 30 'Hinge-side USB-C port window'
capture port-hinge-lsusb lsusb -t
capture port-hinge-dmesg dmesg
capture_class port-hinge-typec /sys/class/typec 'data_role power_role port_type orientation'
capture_class port-hinge-usb-role /sys/class/usb_role 'role'
say 'Now move that USB-C device to the OTHER left USB-C port for 30 seconds.'
say 'If a port is occupied by the charger, skip it; do not unplug power.'
wait_visible 30 'Other USB-C port window'
capture port-other-lsusb lsusb -t
capture port-other-dmesg dmesg
capture_class port-other-typec /sys/class/typec 'data_role power_role port_type orientation'
capture_class port-other-usb-role /sys/class/usb_role 'role'
kill "$PORT_MONITOR_PID" 2>/dev/null || true
wait "$PORT_MONITOR_PID" 2>/dev/null || true
PORT_MONITOR_PID=""
if ! save_logs PORTS && [ "$MOUNTED" -eq 1 ]; then
    stop_now 'STOP: installer FAT remains mounted after the port snapshot.'
fi

say 'Port window finished. Starting ordinary live graphical services.'
capture graphical-start systemctl start --no-block graphical.target
if ! save_logs GRAPHICAL_START && [ "$MOUNTED" -eq 1 ]; then
    stop_now 'STOP: installer FAT remains mounted after the graphical start snapshot.'
fi
say 'Waiting 120 seconds for driver, firmware, network, and desktop attempts.'
wait_visible 120 'Graphical services settling'

capture late-core-dmesg dmesg
capture late-core-journal journalctl -b --no-pager -o short-monotonic
capture late-core-graphical-status systemctl status graphical.target display-manager.service --no-pager --plain
if compgen -G '/dev/dri/renderD*' >/dev/null; then
    say 'A DRM render node exists; later graphics probes will identify its driver.'
else
    say 'No DRM render node is visible; native GPU acceleration is not established.'
fi
if ! save_logs LATE_CORE && [ "$MOUNTED" -eq 1 ]; then
    stop_now 'STOP: installer FAT remains mounted after the late core snapshot.'
fi

capture late-uname uname -a
capture late-cpu lscpu
capture late-memory free -h
capture late-dmesg dmesg
capture late-journal journalctl -b --no-pager -o short-monotonic
capture late-systemd-failed systemctl --failed --no-pager --plain
capture late-systemd-units systemctl list-units --all --no-pager --plain
capture late-graphical-status systemctl status graphical.target display-manager.service --no-pager --plain
capture late-systemd-blame systemd-analyze blame --no-pager
capture late-lsmod lsmod
capture late-lspci lspci -nnvvk
capture late-lsusb lsusb -tv
capture late-lsblk lsblk -o NAME,PATH,TYPE,FSTYPE,LABEL,UUID,SIZE,RO,MOUNTPOINTS
capture late-mounts findmnt -R
capture late-udev-db udevadm info --export-db
capture late-input cat /proc/bus/input/devices
capture late-interrupts cat /proc/interrupts
capture late-drm-nodes bash -c 'ls -la /dev/dri /dev/accel /sys/class/drm /sys/kernel/debug/dri 2>&1'
capture late-gpu-acpi bash -c 'for d in /sys/bus/acpi/devices/QCOM0FF5:00 /sys/bus/platform/devices/QCOM0FF5:00; do echo "### $d"; ls -ld "$d" "$d/driver" "$d/physical_node" 2>&1; for f in hid modalias path status uevent; do if [ -r "$d/$f" ]; then echo "### $f"; cat "$d/$f"; fi; done; done'
capture late-eglinfo eglinfo -B
capture late-vulkaninfo vulkaninfo --summary
capture late-glxinfo glxinfo -B
capture late-modinfo-msm modinfo msm
capture late-modinfo-ath12k modinfo ath12k_wifi7
capture late-modinfo-ath12k-core modinfo ath12k
capture late-modinfo-btqca modinfo btqca
capture late-firmware bash -c 'for d in /lib/firmware/ath12k/QCC2072 /lib/firmware/qcom /lib/firmware/updates; do [ ! -d "$d" ] || find "$d" -maxdepth 4 -type f -printf "%p %s bytes\n"; done'
capture late-packages dpkg-query -W linux-firmware 'linux-image-*' 'libdrm*' 'mesa-*'
capture late-network bash -c 'ip -d link; iw dev; rfkill list; nmcli -f GENERAL,IP4,IP6 device show'
capture late-bluetooth bash -c 'bluetoothctl show; hciconfig -a'
capture late-audio bash -c 'cat /proc/asound/cards; aplay -l; arecord -l'
capture late-power bash -c 'upower -d; cat /sys/power/state /sys/power/mem_sleep'
capture late-kernel-config bash -c 'if [ -r /proc/config.gz ]; then zcat /proc/config.gz; elif [ -r "/boot/config-$(uname -r)" ]; then cat "/boot/config-$(uname -r)"; fi'
capture late-efi bash -c 'efibootmgr -v; mokutil --sb-state'
capture late-dmi dmidecode
capture late-soundwire bash -c 'find /sys/bus/soundwire/devices -maxdepth 1 -mindepth 1 -printf "%f\n" 2>&1'

capture_class late-drm /sys/class/drm 'status enabled modes'
capture_class late-power-supply /sys/class/power_supply 'type present online status capacity energy_now energy_full power_now charge_now charge_full current_now voltage_now voltage_min_design'
capture_class late-thermal /sys/class/thermal 'type temp policy mode'
capture_class late-hwmon /sys/class/hwmon 'name temp1_input temp2_input fan1_input'
capture_class late-cpufreq /sys/devices/system/cpu/cpufreq 'scaling_driver scaling_governor scaling_cur_freq scaling_min_freq scaling_max_freq related_cpus'
capture_class late-cpuidle /sys/devices/system/cpu/cpuidle 'current_driver current_governor_ro'
capture_class late-typec /sys/class/typec 'data_role power_role port_type orientation preferred_role'
capture_class late-usb-role /sys/class/usb_role 'role'
capture_class late-rfkill /sys/class/rfkill 'name type state soft hard'
capture_class late-net /sys/class/net 'type operstate carrier speed'
capture_class late-bluetooth-class /sys/class/bluetooth 'address name'
capture_class late-sound /sys/class/sound 'id'
capture_class late-leds /sys/class/leds 'brightness max_brightness trigger'
capture_class late-i2c /sys/class/i2c-adapter 'name'
capture_class late-remoteproc /sys/class/remoteproc 'name state firmware'
capture_class late-platform /sys/bus/platform/devices 'modalias uevent'
capture_class late-acpi /sys/bus/acpi/devices 'hid path status modalias'
if ! save_logs LATE && [ "$MOUNTED" -eq 1 ]; then
    stop_now 'STOP: installer FAT remains mounted after the late inventory.'
fi

# A failed PCI probe can be retried by binding the *same* registered driver.
# Only copy upstream images into the ephemeral live root after exact device and
# SHA-256 checks; never overwrite an image supplied by the distribution.
wifi_firmware_retry() {
    local pci=/sys/bus/pci/devices/0004:01:00.0
    local driver=/sys/bus/pci/drivers/ath12k_wifi7_pci
    local src=/cdrom/glymur-tools/firmware/ath12k/QCC2072/hw1.0
    local dest=/lib/firmware/ath12k/QCC2072/hw1.0
    local fw_hash=4c6a1be1f5bfad76319755ff76904abb21c4c7ece5293cc5f33a20b1f4c35254
    local board_hash=6880d8e6d51292f6bb5f855965b4c2d1bca3fa0d8a70e68bd693d1e73ff43bf1
    local status=SKIPPED reason=unknown

    if [ "$(uname -r)" != 7.0.0-30-generic ] ||
        [ "$(uname -m)" != aarch64 ]; then
        reason=unexpected_live_kernel
    elif [ ! -d "$pci" ] || [ "$(cat "$pci/vendor" 2>/dev/null)" != 0x17cb ] ||
        [ "$(cat "$pci/device" 2>/dev/null)" != 0x1112 ] ||
        [ "$(cat "$pci/subsystem_vendor" 2>/dev/null)" != 0x103c ] ||
        [ "$(cat "$pci/subsystem_device" 2>/dev/null)" != 0x8ef3 ]; then
        reason=unexpected_pci_identity
    elif [ -L "$pci/driver" ]; then
        reason=already_bound
    elif [ ! -d "$driver" ]; then
        reason=driver_not_registered
    elif [ ! -f "$src/firmware-2.bin" ] || [ ! -f "$src/board-2.bin" ]; then
        reason=upstream_files_missing
    elif [ "$(sha256sum "$src/firmware-2.bin" | cut -d ' ' -f 1)" != "$fw_hash" ] ||
        [ "$(sha256sum "$src/board-2.bin" | cut -d ' ' -f 1)" != "$board_hash" ]; then
        reason=upstream_hash_mismatch
    elif compgen -G "$dest/firmware-2.bin*" >/dev/null ||
        compgen -G "$dest/board-2.bin*" >/dev/null; then
        reason=distribution_firmware_present
    elif ! mkdir -p "$dest" || ! cp "$src/firmware-2.bin" "$src/board-2.bin" "$dest/"; then
        reason=live_root_copy_failed
    else
        say 'Trying one QCC2072 probe with verified upstream Linux firmware in RAM.'
        timeout --kill-after=3s 45s bash -c \
            'printf "%s" 0004:01:00.0 > /sys/bus/pci/drivers/ath12k_wifi7_pci/bind' \
            >"$DATA/wifi-bind.txt" 2>&1
        status=$?
        reason=bind_exit_status
        wait_visible 45 'Wi-Fi probe settling'
    fi
    printf 'status=%s\nreason=%s\n' "$status" "$reason" >"$DATA/wifi-trial-result.txt"
    capture wifi-after-dmesg dmesg
    capture wifi-after-lspci lspci -nnk -s 0004:01:00.0
    capture wifi-after-network bash -c 'ip -d link; iw dev; rfkill list'
    capture wifi-after-journal journalctl -b -k --no-pager -o short-monotonic
    if ! save_logs WIFI && [ "$MOUNTED" -eq 1 ]; then
        stop_now 'STOP: installer FAT remains mounted after the Wi-Fi snapshot.'
    fi
}

wifi_firmware_retry

printf 'finished_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
    >>"$DATA/collector-info.txt"
if save_logs COMPLETE; then
    say 'Whole-system inventory complete; powering off in 30 seconds.'
else
    say 'Final save failed; the EARLY snapshot may still be on the installer.'
    say 'Powering off in 60 seconds.'
    wait_visible 30 'Final save failed; powering off'
fi
wait_visible 30 'Collector finished; powering off'
