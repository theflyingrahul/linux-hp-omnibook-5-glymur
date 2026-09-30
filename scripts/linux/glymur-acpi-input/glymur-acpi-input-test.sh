#!/usr/bin/env bash

# Default-off staged ACPI input test on the live image. See README.md.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

EXPECTED_UUID=1F0F-186A  # Rufus re-image 2026-09-26 (was 07F8-1419)
EXPECTED_KERNEL=7.0.0-30-generic
KIT=/cdrom/glymur-tools/acpi-input
GPIO_KO="$KIT/glymur_acpi_gpio.ko"
I2C_KO="$KIT/glymur_geni_i2c.ko"
COUNTER="$KIT/glymur-input-counter.py"
# Filled in by the staging step from the build's SHA256SUMS.
GPIO_SHA256=@GPIO_SHA256@
I2C_SHA256=@I2C_SHA256@
COUNTER_SHA256=@COUNTER_SHA256@
# Private HP board-2.bin (never committed); "none" skips the Wi-Fi stage.
WIFI_BOARD_SHA256=@WIFI_BOARD_SHA256@
# I2C1 keyboard, I2C5 touchpad, I2C9 touchscreen, IC10 EC.
BASE_HID="0xb80000,0xb90000"
BASE_TOUCH=0xa80000
BASE_EC=0xa84000

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf unknown)"
WORK="$(mktemp -d /run/glymur-acpi-input.XXXXXX)" || exit 1
DATA="$WORK/data"
mkdir -p "$DATA" "$WORK/media" || exit 1
MEDIA_SERIAL=""
OUTPUT_NAME=""
MOUNTED=0
PROGRESS_TTY=/dev/tty6

show_progress() {
    if command -v chvt >/dev/null 2>&1; then
        chvt 6 >/dev/null 2>&1 || true
        if [ -w "$PROGRESS_TTY" ]; then
            {
                printf '\033[H\033[2J'
                printf 'GLYMUR ACPI INPUT TEST\n\n'
                printf 'Do not remove the installer USB. Follow TYPE / TOUCH prompts;\n'
                printf 'otherwise just wait. The machine powers off by itself.\n\n'
                tail -n 12 "$DATA/progress.log" 2>/dev/null || true
            } >"$PROGRESS_TTY" 2>/dev/null || true
        fi
    fi
}

say() {
    printf '%s\n' "$*" | tee -a "$DATA/progress.log" >/dev/console
    show_progress
}

wait_visible() {
    local seconds="$1" label="$2" step
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
    timeout --kill-after=3s 20s "$@" >"$DATA/$name.txt" 2>&1
    status=$?
    printf '%s status=%s\n' "$name" "$status" >>"$DATA/commands.log"
    return 0
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
            dest="$(mktemp -d "$media_root/glymur-logs/acpi-input-$RUN_ID.XXXXXX")" || true
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

checkpoint() {
    if ! save_logs "$1" && [ "$MOUNTED" -eq 1 ]; then
        stop_now "STOP: installer FAT remains mounted after the $1 checkpoint."
    fi
}

snapshot() {
    local tag="$1"
    capture "$tag-dmesg" dmesg
    capture "$tag-lsmod" lsmod
    capture "$tag-interrupts" cat /proc/interrupts
    capture "$tag-input" cat /proc/bus/input/devices
    capture "$tag-i2c" bash -c 'for d in /sys/bus/i2c/devices/*; do
        [ -e "$d" ] || continue
        printf "### %s\nname=%s\nmodalias=%s\ndriver=%s\nfirmware_node=%s\n" "$d" \
            "$(cat "$d/name" 2>/dev/null)" "$(cat "$d/modalias" 2>/dev/null)" \
            "$(readlink -f "$d/driver" 2>/dev/null)" \
            "$(cat "$d/firmware_node/path" 2>/dev/null)"
        done'
    capture "$tag-acpi-platform" bash -c 'for d in /sys/bus/platform/devices/QCOM0F10:* /sys/bus/platform/devices/QCOM0F0C:*; do
        printf "### %s path=%s driver=%s\n" "$d" "$(cat "$d/firmware_node/path" 2>/dev/null)" \
            "$(readlink -f "$d/driver" 2>/dev/null)"
        done'
    capture "$tag-gpio" bash -c 'ls -l /sys/bus/gpio/devices 2>&1; cat /sys/kernel/debug/gpio 2>&1'
    capture "$tag-hid" bash -c 'for d in /sys/bus/hid/devices/*; do
        printf "### %s driver=%s\n" "$d" "$(readlink -f "$d/driver" 2>/dev/null)"; done'
}

# Resolve the QCOM0F10 platform device for an ACPI path such as \_SB_.I2C9.
platform_for_acpi_path() {
    local want="$1" d
    for d in /sys/bus/platform/devices/QCOM0F10:*; do
        if [ "$(cat "$d/firmware_node/path" 2>/dev/null)" = "$want" ]; then
            basename "$d"
            return 0
        fi
    done
    return 1
}

bind_bus() {
    local label="$1" base="$2" acpi_path="$3" dev
    local param=/sys/module/glymur_geni_i2c/parameters/allow
    local driver=/sys/bus/platform/drivers/glymur_acpi_geni_i2c
    if ! dev="$(platform_for_acpi_path "$acpi_path")"; then
        say "$label: no platform device for $acpi_path; skipped."
        return 1
    fi
    if [ -L "/sys/bus/platform/devices/$dev/driver" ]; then
        say "$label: $dev already has a driver; skipped."
        return 1
    fi
    printf '%s,%s' "$(cat "$param")" "$base" >"$param"
    say "$label: binding $dev ($acpi_path) now."
    timeout --kill-after=3s 30s bash -c "printf '%s' '$dev' > '$driver/bind'" \
        >"$DATA/bind-$label.txt" 2>&1
    say "$label: bind exit status $?."
    return 0
}

count_input() {
    local tag="$1" seconds="$2"
    capture "$tag-input-before" cat /proc/bus/input/devices
    timeout --kill-after=5s "$((seconds + 15))s" python3 "$COUNTER" --seconds "$seconds" \
        >"$DATA/$tag-events.txt" 2>&1 &
    local pid=$!
    wait_visible "$seconds" "$tag input window"
    wait "$pid" 2>/dev/null || true
    say "$tag events: $(grep -c 'EV_' "$DATA/$tag-events.txt" 2>/dev/null || printf 0) device(s) produced events."
}

kernel_oopsed() {
    dmesg 2>/dev/null | grep -qE 'Internal error: Oops|Unable to handle kernel|BUG: '
}

# Save and restart: after an oops a normal poweroff hangs (see README.md).
finish() {
    capture late-journal journalctl -b -k --no-pager -o short-monotonic
    printf 'finished_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
        >>"$DATA/collector-info.txt"
    if save_logs COMPLETE; then
        say 'ACPI input test complete.'
    else
        say 'Final save failed; earlier checkpoints may still be on the installer.'
    fi
    if kernel_oopsed; then
        say 'A kernel oops occurred, so a normal poweroff would hang.'
        say 'Restarting in 30 seconds. At the HP logo or GRUB menu, hold the power button.'
        wait_visible 30 'Emergency restart'
        sync
        echo 1 >/proc/sys/kernel/sysrq 2>/dev/null
        echo b >/proc/sysrq-trigger
    fi
    say 'Powering off in 30 seconds.'
    wait_visible 30 'Collector finished; powering off'
    exit 0
}

# ---- Preconditions -------------------------------------------------------
say "Glymur ACPI input test: $RUN_ID"
if ! grep -qw toram /proc/cmdline || ! grep -qw nopersistent /proc/cmdline; then
    stop_now 'STOP: toram nopersistent is required.'
fi
if [ "$(findmnt -no FSTYPE /cdrom 2>/dev/null || true)" != tmpfs ]; then
    stop_now 'STOP: /cdrom is not RAM-backed; do not remove or alter the installer.'
fi
if [ "$(uname -r)" != "$EXPECTED_KERNEL" ] || [ "$(uname -m)" != aarch64 ]; then
    stop_now "STOP: unexpected kernel $(uname -r) $(uname -m)."
fi
INITIAL_DEV="$(timeout 5s blkid -U "$EXPECTED_UUID" 2>/dev/null || true)"
INITIAL_DISK="$(lsblk -no PKNAME "$INITIAL_DEV" 2>/dev/null | head -n 1)"
if [ -z "$INITIAL_DEV" ] || [ -z "$INITIAL_DISK" ] || [ ! -b "/dev/$INITIAL_DISK" ]; then
    stop_now 'STOP: expected installer disk is absent.'
fi
MEDIA_SERIAL="$(udevadm info -q property -n "/dev/$INITIAL_DISK" 2>/dev/null |
    sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1)"
if [ -z "$MEDIA_SERIAL" ] || ! media_device >/dev/null; then
    stop_now 'STOP: installer FAT UUID, type, or serial did not verify.'
fi
for pair in "$GPIO_KO:$GPIO_SHA256" "$I2C_KO:$I2C_SHA256" "$COUNTER:$COUNTER_SHA256"; do
    file="${pair%%:*}"
    if [ "$(sha256sum "$file" 2>/dev/null | cut -d ' ' -f 1)" != "${pair##*:}" ]; then
        stop_now "STOP: hash mismatch or missing file: $file"
    fi
done
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

printf 'run_id=%s\ncollector=acpi-input\ncollector_version=2\n' "$RUN_ID" >"$DATA/collector-info.txt"
printf 'gpio_sha256=%s\ni2c_sha256=%s\n' "$GPIO_SHA256" "$I2C_SHA256" >>"$DATA/collector-info.txt"
capture cmdline cat /proc/cmdline
capture uname uname -a
snapshot early
checkpoint EARLY

# ---- Stage 0: Wi-Fi with the HP board data (RAM only) ---------------------
wifi_trial() {
    local pci=/sys/bus/pci/devices/0004:01:00.0
    local driver=/sys/bus/pci/drivers/ath12k_wifi7_pci
    local fw_src=/cdrom/glymur-tools/firmware/ath12k/QCC2072/hw1.0/firmware-2.bin
    local board_src="$KIT/wifi/board-2.bin"
    local dest=/lib/firmware/ath12k/QCC2072/hw1.0
    local fw_hash=4c6a1be1f5bfad76319755ff76904abb21c4c7ece5293cc5f33a20b1f4c35254
    local status=SKIPPED reason=unknown iface

    if [ "$WIFI_BOARD_SHA256" = none ]; then
        reason=no_board_in_kit
    elif [ ! -d "$pci" ] || [ "$(cat "$pci/vendor" 2>/dev/null)" != 0x17cb ] ||
        [ "$(cat "$pci/device" 2>/dev/null)" != 0x1112 ] ||
        [ "$(cat "$pci/subsystem_vendor" 2>/dev/null)" != 0x103c ] ||
        [ "$(cat "$pci/subsystem_device" 2>/dev/null)" != 0x8ef3 ]; then
        reason=unexpected_pci_identity
    elif [ -L "$pci/driver" ]; then
        reason=already_bound
    elif [ ! -d "$driver" ]; then
        reason=driver_not_registered
    elif [ "$(sha256sum "$fw_src" 2>/dev/null | cut -d ' ' -f 1)" != "$fw_hash" ] ||
        [ "$(sha256sum "$board_src" 2>/dev/null | cut -d ' ' -f 1)" != "$WIFI_BOARD_SHA256" ]; then
        reason=hash_mismatch
    elif compgen -G "$dest/firmware-2.bin*" >/dev/null ||
        compgen -G "$dest/board-2.bin*" >/dev/null; then
        reason=distribution_firmware_present
    elif ! mkdir -p "$dest" || ! cp "$fw_src" "$board_src" "$dest/"; then
        reason=live_root_copy_failed
    else
        say 'Stage 0: one QCC2072 probe with upstream firmware and HP board data (RAM only).'
        timeout --kill-after=3s 45s bash -c \
            'printf "%s" 0004:01:00.0 > /sys/bus/pci/drivers/ath12k_wifi7_pci/bind' \
            >"$DATA/wifi-bind.txt" 2>&1
        status=$?
        reason=bind_exit_status
        wait_visible 30 'Wi-Fi probe settling'
        iface="$(ls "$pci/net" 2>/dev/null | head -n 1)"
        if [ -n "$iface" ]; then
            say "Wi-Fi interface $iface present; running one scan (counts only)."
            ip link set "$iface" up >"$DATA/wifi-up.txt" 2>&1
            sleep 3
            # Record only how many networks and which channels, not their names.
            capture wifi-scan-summary bash -c "iw dev '$iface' scan 2>&1 |
                awk '/^BSS /{n++} /freq:/{f[\$2]++} END{print \"bss_count=\" n+0;
                for (k in f) print \"freq \" k \" count=\" f[k]}'"
            capture wifi-link bash -c "iw dev '$iface' info; iw reg get; ip -d link show '$iface'"
        fi
    fi
    printf 'status=%s\nreason=%s\n' "$status" "$reason" >"$DATA/wifi-trial-result.txt"
    say "Wi-Fi trial: $reason (status $status)."
    capture wifi-dmesg bash -c 'dmesg | grep -iE "ath12k|mhi|qcc2072|wlan"'
    capture wifi-lspci lspci -nnk -s 0004:01:00.0
}
wifi_trial
checkpoint WIFI

# ---- Stage 1: ACPI TLMM GPIO (touches only allow-listed pins) ------------
say 'Stage 1: loading the ACPI GPIO module (pins 3, 51, 67, 92 only).'
checkpoint BEFORE_GPIO
timeout --kill-after=5s 30s insmod "$GPIO_KO" enable=1 >"$DATA/insmod-gpio.txt" 2>&1
say "GPIO insmod exit status $?."
sleep 3
snapshot gpio
checkpoint GPIO

# ---- Stage 2: keyboard and touchpad buses ---------------------------------
say 'Stage 2: loading the ACPI I2C module for I2C1 (keyboard) and I2C5 (touchpad).'
checkpoint BEFORE_I2C
timeout --kill-after=5s 30s insmod "$I2C_KO" allow="$BASE_HID" >"$DATA/insmod-i2c.txt" 2>&1
I2C_STATUS=$?
say "I2C insmod exit status $I2C_STATUS."
if kernel_oopsed || [ "$I2C_STATUS" -ne 0 ]; then
    # A crashed probe keeps its device lock: save and stop here.
    say 'I2C module failed to load; skipping the input, touchscreen, and EC stages.'
    snapshot i2c
    finish
fi
modprobe i2c_hid_acpi >"$DATA/modprobe-i2c-hid.txt" 2>&1 || true
modprobe hid_multitouch >>"$DATA/modprobe-i2c-hid.txt" 2>&1 || true
wait_visible 15 'Waiting for HID devices'
snapshot i2c
checkpoint I2C

say '>>> TYPE on the laptop keyboard and MOVE/CLICK on the touchpad now. <<<'
say '    Only event counts are recorded, never which keys were pressed.'
count_input hid 45
snapshot hid-after
checkpoint INPUT

# ---- Stage 3: touchscreen bus (not previously read) ------------------------
say 'Stage 3: binding I2C9 (touchscreen). A hang here still leaves stages 1-2 saved.'
checkpoint BEFORE_TOUCH
if bind_bus touch "$BASE_TOUCH" '\_SB_.I2C9'; then
    wait_visible 10 'Waiting for touchscreen'
    say '>>> TOUCH and drag on the SCREEN now. <<<'
    count_input touch 30
fi
snapshot touch
checkpoint TOUCH

# ---- Stage 4: embedded-controller bus (lid/EC AML) --------------------------
# See README.md for what uses the EC in this test.
say 'Stage 4: binding IC10 (embedded controller) for lid/EC availability only.'
capture ec-lid-before bash -c 'cat /proc/acpi/button/lid/*/state 2>&1'
capture ec-wmi-modules bash -c 'lsmod | grep -iE "wmi" || echo "no wmi modules loaded"'
checkpoint BEFORE_EC
if bind_bus ec "$BASE_EC" '\_SB_.IC10'; then
    wait_visible 20 'Waiting for EC availability (_REG) and lid methods'
fi
capture ec-lid-after bash -c 'cat /proc/acpi/button/lid/*/state 2>&1'
snapshot ec
capture ec-power-supply bash -c 'for d in /sys/class/power_supply/*; do
    echo "### $d"; for f in type online status capacity energy_now energy_full power_now voltage_now technology; do
    [ -r "$d/$f" ] && echo "$f=$(cat "$d/$f" 2>&1)"; done; done'
capture ec-thermal bash -c 'for d in /sys/class/thermal/thermal_zone*; do echo "$d $(cat $d/type 2>&1) $(cat $d/temp 2>&1)"; done'
capture ec-acpi-errors bash -c 'dmesg | grep -iE "acpi.*(error|exception|ae_)|GenericSerialBus|i2c.*acpi"'
checkpoint EC

finish
