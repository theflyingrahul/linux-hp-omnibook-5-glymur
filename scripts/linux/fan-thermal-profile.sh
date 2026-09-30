#!/usr/bin/env bash
set -u

# Linux twin of scripts/windows/fan-thermal-profile.ps1. See README.md.
# Usage: [POWER_SOURCE=battery|ac] fan-thermal-profile.sh [out-dir]

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$REPO/.work}"
IDLE=${IDLE_SECONDS:-60}
LOAD=${LOAD_SECONDS:-60}
RECOVERY=${RECOVERY_SECONDS:-120}
INTERVAL=${INTERVAL_SECONDS:-5}

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/linux-fan-profile-$(date +%Y%m%dT%H%M%S).tsv"
printf 'time\tphase\telapsed_s\tsource\tname\tvalue\tunit\n' >"$OUT"
# Linux cannot see the AC state yet: pass POWER_SOURCE by hand.
{
    printf '# power_source %s\n' "${POWER_SOURCE:-unknown}"
    printf '# kernel %s\n' "$(uname -r)"
    printf '# cmdline %s\n' "$(cat /proc/cmdline)"
} >"$OUT.meta"

read_cpu() { awk '/^cpu /{ idle=$5+$6; t=0; for (i=2;i<=NF;i++) t+=$i; print t, idle }' /proc/stat; }
PREV="$(read_cpu)"

sample() {
    local phase="$1" elapsed="$2" stamp f name v fans="" cur total idle ptotal pidle util
    stamp="$(date --iso-8601=seconds)"
    for f in /sys/bus/acpi/devices/PNP0C0B:*/physical_node*/fan_speed_rpm \
        /sys/class/hwmon/hwmon*/fan*_input; do
        [ -r "$f" ] || continue
        v="$(cat "$f" 2>/dev/null)" || continue
        name="${f#/sys/}"
        printf '%s\t%s\t%s\tfan\t%s\t%s\tRPM\n' "$stamp" "$phase" "$elapsed" "$name" "$v" >>"$OUT"
        fans="$fans $v"
    done
    for f in /sys/class/thermal/thermal_zone*; do
        v="$(cat "$f/temp" 2>/dev/null)" || continue
        name="$(basename "$f"):$(cat "$f/type" 2>/dev/null)"
        [ -r "$f/device/path" ] && name="$name:$(cat "$f/device/path")"
        printf '%s\t%s\t%s\tthermal_zone\t%s\t%s\tC\n' "$stamp" "$phase" "$elapsed" "$name" \
            "$(awk -v t="$v" 'BEGIN { printf "%.1f", t / 1000 }')" >>"$OUT"
    done
    cur="$(read_cpu)"
    read -r total idle <<<"$cur"
    read -r ptotal pidle <<<"$PREV"
    PREV="$cur"
    util="$(awk -v t=$((total - ptotal)) -v i=$((idle - pidle)) \
        'BEGIN { printf "%.1f", (t > 0 ? 100 * (t - i) / t : 0) }')"
    printf '%s\t%s\t%s\tcpu\tutility\t%s\t%%\n' "$stamp" "$phase" "$elapsed" "$util" >>"$OUT"
    for f in /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq; do
        [ -r "$f" ] || continue
        printf '%s\t%s\t%s\tcpufreq\t%s\t%s\tkHz\n' "$stamp" "$phase" "$elapsed" \
            "$(basename "$(dirname "$f")")" "$(cat "$f")" >>"$OUT"
    done
    for f in /sys/class/power_supply/*/online; do
        [ -r "$f" ] || continue
        printf '%s\t%s\t%s\tpower\t%s\t%s\t\n' "$stamp" "$phase" "$elapsed" \
            "$(basename "$(dirname "$f")")" "$(cat "$f")" >>"$OUT"
    done
    printf '%-9s t=%4ss cpu=%5s%% fan_rpm=%s\n' "$phase" "$elapsed" "$util" "${fans:- none}"
}

LOAD_PIDS=()
stop_load() {
    [ "${#LOAD_PIDS[@]}" -gt 0 ] && kill "${LOAD_PIDS[@]}" 2>/dev/null
    LOAD_PIDS=()
}
trap stop_load EXIT INT TERM

START=$SECONDS
run_phase() {
    local phase="$1" end=$((SECONDS + $2))
    while [ "$SECONDS" -lt "$end" ]; do
        sample "$phase" $((SECONDS - START))
        sleep "$INTERVAL"
    done
}

run_phase idle "$IDLE"
for _ in $(seq "$(nproc)"); do
    sh -c 'while :; do :; done' &
    LOAD_PIDS+=($!)
done
run_phase load "$LOAD"
stop_load
run_phase recovery "$RECOVERY"
echo "Saved $OUT"
