#!/usr/bin/env bash
set -u

# One-boot GPU, display, cpufreq and charging check. See README.md.
#   sudo bash check-gpu-test.sh [--charging] [--cpufreq]

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
CHARGING=0 CPUFREQ=0
for a in "$@"; do
    case "$a" in
        --charging) CHARGING=1 ;;
        --cpufreq) CPUFREQ=1 ;;
        *) echo "unknown option $a" >&2; exit 2 ;;
    esac
done
OUT="/var/log/glymur/gpu-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s (%s)\n' "$*" "$(date +%T.%N)"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1; }

sect system
run uname -a
run cat /proc/cmdline
run cat /sys/firmware/devicetree/base/model; echo

sect "GPU and display: kernel log"
journalctl -k -b --no-pager | grep -iE 'adreno|a6xx|a8xx|gmu|gpu|msm|dpu|drm|gpucc|gxclkctl|3da0000|smmu|zap|secvid|firmware' | tail -250

sect "DRM devices"
run ls -l /dev/dri /dev/dri/by-path
for c in /sys/class/drm/card*; do
    [ -e "$c/device/driver" ] && printf '%s -> %s\n' "$c" "$(basename "$(readlink -f "$c/device/driver")")"
done
for c in /sys/class/drm/card*-*; do
    [ -f "$c/status" ] && printf '%s status=%s enabled=%s modes=%s\n' "$(basename "$c")" "$(cat "$c/status")" "$(cat "$c/enabled")" "$(head -1 "$c/modes" 2>/dev/null)"
done
run ls /sys/bus/platform/drivers/msm_dpu /sys/bus/platform/drivers/adreno 2>/dev/null

sect "GPU devfreq and debugfs"
for d in /sys/class/devfreq/*; do
    [ -e "$d" ] || continue
    printf '%s: governor=%s cur=%s min=%s max=%s\navail=%s\n' "$d" "$(cat "$d/governor")" "$(cat "$d/cur_freq")" "$(cat "$d/min_freq")" "$(cat "$d/max_freq")" "$(cat "$d/available_frequencies")"
done
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
for f in /sys/kernel/debug/dri/*/gpu; do [ -f "$f" ] && { echo "--- $f"; head -60 "$f"; }; done

sect "userspace GL/Vulkan (if the tools are installed)"
u="$(logname 2>/dev/null || echo "${SUDO_USER:-}")"
if command -v glxinfo >/dev/null && [ -n "$u" ]; then
    sudo -u "$u" DISPLAY=:0 glxinfo -B 2>&1 | head -30
else
    echo 'glxinfo not installed (apt install mesa-utils) or no desktop user'
fi
command -v eglinfo >/dev/null && eglinfo -B 2>&1 | head -40
command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>&1 | head -40

sect "thermal (GPU zones)"
for z in /sys/class/thermal/thermal_zone*; do
    t="$(cat "$z/type")"; case "$t" in *gpu*) printf '%s %s\n' "$t" "$(cat "$z/temp")" ;; esac
done

snapshot() {
    sect "power snapshot: $1"
    for p in /sys/class/power_supply/*; do echo "--- $p"; cat "$p/uevent"; done
    for p in /sys/class/typec/port*; do
        echo "--- $p"
        for a in data_role power_role power_operation_mode orientation; do
            [ -f "$p/$a" ] && printf '%s=%s\n' "$a" "$(cat "$p/$a")"
        done
        ls -d "$p"/port*-partner 2>/dev/null
    done
    journalctl -k -b --no-pager --since '-2min' | grep -iE 'ucsi|typec|pmic_glink|battmgr|power_supply' | tail -30
}
snapshot "now"
if [ "$CHARGING" = 1 ]; then
    read -r -p 'Unplug the charger, then press Enter. ' _
    sleep 10; snapshot "unplugged"
    read -r -p 'Plug the charger into the same port, then press Enter. ' _
    sleep 20; snapshot "replugged (20 s)"
fi
sync

if [ "$CPUFREQ" = 1 ]; then
    sect "cpufreq: loading scmi-cpufreq (polling SCMI transport)"
    [ -e /sys/firmware/devicetree/base/firmware/scmi/arm,no-completion-irq ] && echo 'polling property present' || echo 'polling property ABSENT'
    sync
    run modprobe scmi-cpufreq
    sleep 3
    run ls /sys/devices/system/cpu/cpufreq/
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] && printf '%s: cpus=%s cur=%s min=%s max=%s driver=%s\n' "$p" "$(cat "$p/related_cpus")" "$(cat "$p/scaling_cur_freq")" "$(cat "$p/cpuinfo_min_freq")" "$(cat "$p/cpuinfo_max_freq")" "$(cat "$p/scaling_driver")"
    done
    journalctl -k -b --no-pager --since '-1min' | grep -iE 'scmi|cpufreq|cpucp|mbox' | tail -30
fi
sync
echo; echo "Saved to $OUT"
