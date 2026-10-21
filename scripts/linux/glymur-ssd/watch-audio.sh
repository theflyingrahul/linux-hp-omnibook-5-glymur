#!/usr/bin/env bash
set -u

# Logs what the speaker amplifiers and their rails do over time, to find
# what makes them leave the SoundWire bus (docs/audio-speakers-down-2026-10-21.md,
# docs/kernel-16-plan-2026-10-21.md). One line a second while nothing
# changes, a full dump whenever an amplifier's status or a runtime-PM state
# changes, and the SoundWire driver's debug messages. Leave it running in a
# terminal while using the laptop normally; stop with Ctrl-C.
#   sudo bash watch-audio.sh [seconds, default 1800]

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
DUR="${1:-1800}"
OUT="/var/log/glymur/audio-watch-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1

DYN=/sys/kernel/debug/dynamic_debug/control
if [ -w "$DYN" ]; then
    for f in drivers/soundwire/qcom.c drivers/soundwire/bus.c drivers/soundwire/slave.c \
             sound/soc/codecs/wsa884x.c; do
        echo "file $f +p" > "$DYN" 2>&1
    done
fi

state() {
    local d s
    for d in /sys/bus/soundwire/devices/sdw:*; do
        [ -e "$d" ] || continue
        printf '%s=%s/%s ' "${d##*:}" "$(cat "$d/status" 2>/dev/null)" \
            "$(cat "$d/power/runtime_status" 2>/dev/null)"
    done
    for d in /sys/bus/platform/devices/6c80000.soundwire /sys/bus/platform/devices/6c90000.codec; do
        printf 'master=%s ' "$(cat "$d/power/runtime_status" 2>/dev/null)"
    done
    for s in /sys/class/regulator/regulator.*; do
        case "$(cat "$s/name" 2>/dev/null)" in
            vreg_l15b*|vreg_l18b*) printf '%s=%s/%s ' "$(cat "$s/name")" \
                "$(cat "$s/state" 2>/dev/null)" "$(cat "$s/microvolts" 2>/dev/null)" ;;
        esac
    done
    echo
}
dump() {
    echo "---- dump $(date +%T)"
    for d in /sys/bus/soundwire/devices/sdw:*; do
        [ -e "$d" ] && echo "$(basename "$d") status=$(cat "$d/status" 2>/dev/null) pm=$(cat "$d/power/runtime_status" 2>/dev/null)"
    done
    awk '/^gpiochip/ { lp = /7760000/ } lp && / gpio1[23] /' /sys/kernel/debug/gpio 2>/dev/null
    grep -H . /sys/class/regulator/regulator.*/{name,state,microvolts,use_count} 2>/dev/null | grep -i 'l15b\|l18b' -A3
    journalctl -k --since "-20s" --no-pager 2>/dev/null | grep -i 'soundwire\|swr\|wsa\|q6apm\|regulator' | tail -15
}

echo "watching for $DUR s, log $OUT"
echo "kernel $(uname -r)"
prev=''
end=$((SECONDS + DUR))
while [ "$SECONDS" -lt "$end" ]; do
    cur="$(state)"
    if [ "$cur" != "$prev" ]; then
        echo "$(date +%T) $cur"
        [ -n "$prev" ] && dump
        prev="$cur"
    fi
    sleep 1
done
echo "done"
