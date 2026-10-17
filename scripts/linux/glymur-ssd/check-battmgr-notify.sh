#!/usr/bin/env bash
set -u

# Count battery-manager notifications while you plug and unplug the
# charger. See README.md.
#   sudo bash check-battmgr-notify.sh [seconds]

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
SECS="${1:-60}"
OUT="/var/log/glymur/battmgr-notify-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
T=/sys/kernel/tracing
mountpoint -q "$T" || mount -t tracefs none "$T"
I="$T/instances/glymur-battmgr"
FUNCS="qcom_battmgr_state_callback qcom_battmgr_callback"

{
    echo "kernel: $(uname -r)"
    for f in $FUNCS; do
        grep -qw "$f" "$T/available_filter_functions" && echo "traceable: $f" || echo "missing: $f"
    done
} | tee "$OUT"

rmdir "$I" 2>/dev/null
mkdir "$I" || { echo "cannot create $I" | tee -a "$OUT"; exit 1; }
cleanup() {
    echo nop > "$I/current_tracer" 2>/dev/null
    rmdir "$I" 2>/dev/null
}
trap cleanup EXIT
for f in $FUNCS; do echo "$f" >> "$I/set_ftrace_filter" 2>/dev/null; done
echo function > "$I/current_tracer"
echo 1 > "$I/tracing_on"

echo "Plug and unplug the charger a few times in the next $SECS s."
for ((i = SECS; i > 0; i -= 10)); do
    printf '%3d s left: ac=%s usb=%s bat=%s\n' "$i" \
        "$(cat /sys/class/power_supply/qcom-battmgr-ac/online 2>/dev/null)" \
        "$(cat /sys/class/power_supply/qcom-battmgr-usb/online 2>/dev/null)" \
        "$(cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null)" | tee -a "$OUT"
    sleep 10
done
echo 0 > "$I/tracing_on"

{
    echo "== calls"
    for f in $FUNCS; do
        printf '%s %s\n' "$f" "$(grep -c " $f <-" "$I/trace")"
    done
    echo "== trace"
    grep -v '^#' "$I/trace"
} | tee -a "$OUT"
echo "Saved to $OUT"
