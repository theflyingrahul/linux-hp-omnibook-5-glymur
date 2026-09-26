#!/usr/bin/env bash

# Run from the Ubuntu live USB with systemd.run=; do not install anything.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

MEDIA=/cdrom
MODULE="$MEDIA/glymur-tools/qcom0f10_inspect.ko"
EXPECTED_KERNEL=7.0.0-30-generic
EXPECTED_SHA256=4aadcd1896e02c54164702152ff789f646ab75b75a323996d2676797115d2adf
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || printf unknown)"
OUTPUT="$MEDIA/glymur-logs/qcom0f10-$RUN_ID"

for ATTEMPT in $(seq 1 60); do
    if mountpoint -q "$MEDIA" 2>/dev/null; then
        break
    fi
    sleep 1
done

case "$(findmnt -no FSTYPE "$MEDIA" 2>/dev/null || true)" in
    vfat|msdos|exfat)
        mount -o remount,rw "$MEDIA" 2>/dev/null || true
        ;;
esac

if ! mkdir -p "$OUTPUT" 2>/dev/null; then
    exit 1
fi

printf 'phase=started\n' >"$OUTPUT/progress.log"
uname -a >"$OUTPUT/uname.txt" 2>&1

if [ "$(uname -r)" != "$EXPECTED_KERNEL" ]; then
    printf 'kernel mismatch: expected %s, got %s\n' \
        "$EXPECTED_KERNEL" "$(uname -r)" >>"$OUTPUT/progress.log"
    sync
    exit 1
fi

if [ ! -r "$MODULE" ]; then
    printf 'module missing: %s\n' "$MODULE" >>"$OUTPUT/progress.log"
    sync
    exit 1
fi

ACTUAL_SHA256="$(sha256sum "$MODULE" | cut -d ' ' -f 1)"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    printf 'module hash mismatch: %s\n' "$ACTUAL_SHA256" >>"$OUTPUT/progress.log"
    sync
    exit 1
fi

dmesg >"$OUTPUT/dmesg-before.txt" 2>&1
printf 'phase=before-insmod\n' >>"$OUTPUT/progress.log"
sync

if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=5s 30s insmod "$MODULE" inspect=1 \
        >"$OUTPUT/insmod.txt" 2>&1
    STATUS=$?
else
    insmod "$MODULE" inspect=1 >"$OUTPUT/insmod.txt" 2>&1
    STATUS=$?
fi

printf 'phase=after-insmod status=%s\n' "$STATUS" >>"$OUTPUT/progress.log"
dmesg >"$OUTPUT/dmesg-after.txt" 2>&1
lsmod >"$OUTPUT/lsmod.txt" 2>&1
sync

if [ "$STATUS" -eq 0 ]; then
    touch "$OUTPUT/COMPLETE"
fi
exit "$STATUS"
