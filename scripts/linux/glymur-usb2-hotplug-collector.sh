#!/usr/bin/env bash

# Observe one right USB-A USB 2.0 hot-plug after a verified Casper RAM boot.
# This script is opt-in and must not be staged on an unhealthy installer.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

EXPECTED_UUID=1F0F-186A  # Rufus re-image 2026-09-26 (was 07F8-1419)
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf unknown)"
WORK="$(mktemp -d /run/glymur-usb2-hotplug.XXXXXX)" || exit 1
DATA="$WORK/data"
mkdir -p "$DATA"
MONITOR_PID=""
OBSERVER_PID=""

say() {
    printf '%s\n' "$*" | tee -a "$DATA/progress.log" >/dev/console
}

stop_now() {
    say "$*"
    say 'No installer removal. Power-off follows in 60 seconds.'
    sleep 60
    exit 1
}

stop_monitor() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
        MONITOR_PID=""
    fi
}
stop_observer() {
    if [ -n "$OBSERVER_PID" ]; then
        kill "$OBSERVER_PID" 2>/dev/null || true
        wait "$OBSERVER_PID" 2>/dev/null || true
        OBSERVER_PID=""
    fi
}
observer_ready() {
    [ -n "$OBSERVER_PID" ] &&
        kill -0 "$OBSERVER_PID" 2>/dev/null &&
        [ -r "/proc/$OBSERVER_PID/status" ] &&
        ! grep -Eq '^State:[[:space:]]*Z' "/proc/$OBSERVER_PID/status" &&
        grep -Eq '^observer_start=.* event_size=24$' "$DATA/mouse-events.txt"
}
trap 'stop_observer; stop_monitor' EXIT

say "Glymur USB 2.0 hot-plug observation: $RUN_ID"
if ! grep -qw toram /proc/cmdline || ! grep -qw nopersistent /proc/cmdline; then
    stop_now 'STOP: expected toram nopersistent kernel options are absent.'
fi
if [ "$(findmnt -no FSTYPE /cdrom 2>/dev/null || true)" != tmpfs ]; then
    stop_now 'STOP: /cdrom is not RAM-backed; do not remove the installer.'
fi
MEDIA_DEV="$(timeout 5s blkid -U "$EXPECTED_UUID" 2>/dev/null || true)"
if [ -z "$MEDIA_DEV" ] || [ "$(blkid -s TYPE -o value "$MEDIA_DEV" 2>/dev/null)" != vfat ]; then
    stop_now 'STOP: the expected installer FAT partition was not found.'
fi
MEDIA_DISK="$(lsblk -no PKNAME "$MEDIA_DEV" 2>/dev/null | head -n 1)"
if [ -z "$MEDIA_DISK" ] || [ ! -b "/dev/$MEDIA_DISK" ]; then
    stop_now 'STOP: cannot identify the installer disk.'
fi
MEDIA_SERIAL="$(udevadm info -q property -n "/dev/$MEDIA_DISK" 2>/dev/null |
    sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1)"
if [ -z "$MEDIA_SERIAL" ]; then
    stop_now 'STOP: cannot read the installer USB serial.'
fi
if lsblk -nr -o MOUNTPOINTS "/dev/$MEDIA_DISK" | grep -q '[^[:space:]]'; then
    stop_now 'STOP: an installer partition is still mounted; do not remove it.'
fi
if ! command -v python3 >/dev/null ||
    [ ! -r /cdrom/glymur-tools/glymur-input-event-observer.py ]; then
    stop_now 'STOP: the staged mouse-event observer or Python 3 is unavailable.'
fi

cat /proc/cmdline >"$DATA/cmdline.txt"
findmnt -R >"$DATA/mounts-before.txt" 2>&1
lsblk -o NAME,PATH,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS >"$DATA/lsblk-before.txt" 2>&1
timeout --kill-after=2s 10s lsusb -t >"$DATA/lsusb-before.txt" 2>&1
cat /proc/bus/input/devices >"$DATA/input-before.txt" 2>&1
dmesg >"$DATA/dmesg-before.txt" 2>&1

udevadm monitor --kernel --udev --subsystem-match=usb \
    >"$DATA/usb-monitor.txt" 2>&1 &
MONITOR_PID=$!
python3 /cdrom/glymur-tools/glymur-input-event-observer.py --duration 80 \
    >"$DATA/mouse-events.txt" 2>&1 &
OBSERVER_PID=$!
sleep 1
if ! observer_ready; then
    stop_now 'STOP: mouse-event observer failed to start; do not swap devices.'
fi

say 'In 15 seconds: remove installer, then insert the wired USB 2.0 mouse'
say 'DIRECTLY into the same right USB-A port. No hub or USB-C adapter.'
sleep 15
if ! observer_ready; then
    stop_now 'STOP: mouse-event observer stopped; do not swap devices.'
fi
say 'Now swap installer for mouse. Leave mouse plugged in for 45 seconds.'
say 'Move the mouse and click its buttons several times during this window.'
sleep 45

timeout --kill-after=2s 10s lsusb -t >"$DATA/lsusb-mouse.txt" 2>&1
cat /proc/bus/input/devices >"$DATA/input-mouse.txt" 2>&1
for dev in /sys/bus/usb/devices/*/uevent; do
    [ -r "$dev" ] || continue
    printf '### %s\n' "$dev" >>"$DATA/usb-uevents-mouse.txt"
    cat "$dev" >>"$DATA/usb-uevents-mouse.txt"
done
dmesg >"$DATA/dmesg-mouse.txt" 2>&1
stop_observer
if ! grep -q '^summary ' "$DATA/mouse-events.txt"; then
    say 'Warning: mouse-event capture did not finish; inspect mouse-events.txt.'
fi

say 'Remove the mouse and reinsert the installer in the right USB-A port.'
say 'Waiting up to 90 seconds for the same installer to return.'
RETURNED=""
for attempt in $(seq 1 90); do
    RETURNED="$(timeout 5s blkid -U "$EXPECTED_UUID" 2>/dev/null || true)"
    if [ -n "$RETURNED" ]; then
        break
    fi
    sleep 1
done

dmesg >"$DATA/dmesg-after.txt" 2>&1
timeout --kill-after=2s 10s lsusb -t >"$DATA/lsusb-after.txt" 2>&1
stop_monitor
say 'Recent USB/HID kernel messages (please photograph if no log is saved):'
grep -Ei 'usb [0-9]+-[0-9]+|hid|input:' "$DATA/dmesg-after.txt" | tail -n 35 >/dev/console || true

if [ -z "$RETURNED" ] || [ "$(blkid -s TYPE -o value "$RETURNED" 2>/dev/null)" != vfat ]; then
    say 'Installer did not return; logs remain in RAM only.'
    sleep 90
    exit 1
fi
RETURNED_DISK="$(lsblk -no PKNAME "$RETURNED" 2>/dev/null | head -n 1)"
if [ -z "$RETURNED_DISK" ] || [ ! -b "/dev/$RETURNED_DISK" ]; then
    say 'Reinserted device has no valid parent disk; refusing to write logs.'
    sleep 90
    exit 1
fi
RETURNED_SERIAL="$(udevadm info -q property -n "/dev/$RETURNED_DISK" 2>/dev/null |
    sed -n 's/^ID_SERIAL_SHORT=//p' | head -n 1)"
if [ -z "$RETURNED_SERIAL" ] || [ "$RETURNED_SERIAL" != "$MEDIA_SERIAL" ]; then
    say 'Installer USB serial differs; refusing to write logs.'
    sleep 90
    exit 1
fi

mkdir -p "$WORK/media"
if ! timeout --kill-after=5s 30s mount -t vfat -o rw,nosuid,nodev,noexec \
    "$RETURNED" "$WORK/media"; then
    say 'Could not mount installer for logs; logs remain in RAM only.'
    sleep 90
    exit 1
fi
if ! mkdir -p "$WORK/media/glymur-logs"; then
    umount "$WORK/media" || true
    say 'Could not create log directory on installer.'
    sleep 90
    exit 1
fi
OUTPUT="$(mktemp -d "$WORK/media/glymur-logs/usb2-hotplug-$RUN_ID.XXXXXX")" || {
    umount "$WORK/media" || true
    say 'Could not allocate log directory on installer.'
    sleep 90
    exit 1
}
if cp -R "$DATA/." "$OUTPUT/" 2>/dev/null && touch "$OUTPUT/COMPLETE"; then
    sync
    say "Saved USB hot-plug logs under glymur-logs/$(basename "$OUTPUT")"
else
    say 'Log copy failed; inspect partial files before another run.'
fi
umount "$WORK/media" || say 'Warning: log partition did not unmount cleanly.'
say 'Observation finished. System will power off after 90 seconds.'
sleep 90
