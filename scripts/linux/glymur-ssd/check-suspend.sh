#!/usr/bin/env bash
set -u

# Supervised s2idle test (kernel -20 on). See README.md.
#   sudo bash check-suspend.sh [--sync-state]
# Three suspend cycles: woken by an RTC alarm, by opening the lid, by the
# power button. Each resume records what came back. Suspend stays unmasked
# only if you say so at the end, after every cycle resumed; if a resume
# hangs and the laptop is powered off, a one-shot unit masks it again at
# the next boot.
# --sync-state first releases the providers still waiting for sync_state
# (the clocks held by the unbound GPU management unit), whose boot votes
# otherwise keep DDR and the SoC rails up in suspend.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
SYNC=0
[ "${1:-}" = --sync-state ] && SYNC=1
OUT="/var/log/glymur/suspend-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
redact() {
    sed -u -E -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
        -e 's/\b[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b/<uuid>/g' \
        -e 's/(SSID|ssid)[ :=]+.*/\1 <ssid>/'
}
exec > >(redact | tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
ask() { local a; read -r -p "$1 " a </dev/tty; printf '%s\n' "$a"; }
TARGETS="sleep.target suspend.target"

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
sed 's/root=[^ ]*/root=…/' /proc/cmdline
echo "mem_sleep: $(cat /sys/power/mem_sleep)   state: $(cat /sys/power/state)"
systemctl is-enabled $TARGETS 2>&1 | paste -sd' ' | sed 's/^/targets: /'

modprobe qcom_stats 2>/dev/null
stats() {
    local d=/sys/kernel/debug/qcom_stats f
    [ -d "$d" ] || { echo "no $d"; return; }
    for f in "$d"/*; do
        printf '%s: ' "${f##*/}"
        tr '\n' ' ' < "$f"
        echo
    done
}
snapshot() {
    sect "sleep counters ($1)"
    stats
    grep -H . /sys/power/suspend_stats/* 2>/dev/null | sed 's#/sys/power/suspend_stats/##'
}
devices() {
    sect "devices ($1)"
    lsusb -t 2>&1
    ip -br link 2>&1 | grep -v '^lo'
    iw dev 2>/dev/null | grep -E 'Interface|type|channel'
    aplay -l 2>&1 | grep -E '^card'
    for p in /sys/class/power_supply/*; do
        printf '%s: %s %s\n' "${p##*/}" "$(cat "$p/status" 2>/dev/null)" "$(cat "$p/capacity" 2>/dev/null)"
    done
    for c in /sys/class/drm/card*-*; do
        printf '%s: %s %s\n' "${c##*/}" "$(cat "$c/status" 2>/dev/null)" "$(cat "$c/enabled" 2>/dev/null)"
    done
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = hp_omnibook5_ec ] || continue
        printf 'EC fan %s rpm, temp1 %s\n' "$(cat "$h/fan1_input" 2>/dev/null)" "$(cat "$h/temp1_input" 2>/dev/null)"
    done
    ls /dev/rtc* 2>/dev/null
}

sect "sync_state still pending at boot"
journalctl -k -b --no-pager | grep -E 'sync_state\(\) pending' | sed 's/^.*kernel: //' | sort -u
if [ "$SYNC" = 1 ]; then
    sect "releasing the waiting providers (state_synced)"
    journalctl -k -b --no-pager | grep -E 'sync_state\(\) pending' |
        sed -E 's/^.*kernel: [^ ]+ ([^:]+): sync_state.*$/\1/' | sort -u |
        while read -r dev; do
            f="/sys/bus/platform/devices/$dev/state_synced"
            if [ -w "$f" ]; then
                echo 1 > "$f" 2>&1 && echo "$dev: released" || echo "$dev: write failed"
            else
                echo "$dev: no writable state_synced"
            fi
        done
fi

sect "power domains still on"
grep -E '^\S+\s+on' /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | head -60

sect "wakeup sources enabled"
for w in /sys/bus/*/devices/*/power/wakeup; do
    [ "$(cat "$w" 2>/dev/null)" = enabled ] && echo "${w%/power/wakeup}" | sed 's#/sys/bus/##'
done | sort

devices before
snapshot before

echo
echo "Suspend is about to be unmasked for this test ($TARGETS)."
[ "$(ask 'Continue? [y/N]')" = y ] || { echo stopped; exit 0; }
# If a resume hangs and the laptop is powered off, the next boot masks
# suspend again before anyone can close the lid.
GUARD=/etc/systemd/system/glymur-suspend-guard.service
cat > "$GUARD" <<UNIT
[Unit]
Description=Mask suspend again after an unfinished check-suspend.sh
DefaultDependencies=no
Before=systemd-logind.service

[Service]
Type=oneshot
ExecStart=/bin/systemctl mask $TARGETS
ExecStart=/bin/rm -f $GUARD /etc/systemd/system/sysinit.target.wants/glymur-suspend-guard.service

[Install]
WantedBy=sysinit.target
UNIT
systemctl daemon-reload
systemctl enable glymur-suspend-guard.service 2>&1 | tail -1
systemctl unmask $TARGETS

cycle() {
    local name=$1 how=$2 t0 before after i
    sect "cycle: $name"
    before=$(cat /sys/power/suspend_stats/success 2>/dev/null || echo 0)
    t0=$(date +%s)
    echo "$how"
    sync
    if [ "$name" = rtc ]; then
        rtcwake -d rtc0 -m no -s 40 2>&1 || echo 'rtcwake failed: wake it with the power button'
        sleep 2
        systemctl suspend
    elif [ "$name" = button ]; then
        sleep 3
        systemctl suspend
    fi
    for i in $(seq 1 240); do
        after=$(cat /sys/power/suspend_stats/success 2>/dev/null || echo 0)
        [ "$after" -gt "$before" ] && break
        sleep 1
    done
    sleep 8
    echo "resumed after $(( $(date +%s) - t0 )) s; suspend successes $before -> $after"
    sect "kernel log of the cycle"
    journalctl -k --no-pager --since "@$t0" -o short-monotonic | tail -250
    devices "after $name"
    snapshot "after $name"
    echo
    ask "Cycle $name: did the screen, keyboard and touchpad come back? [y/N]" > /tmp/glymur-cycle-$name
    echo "owner: $(cat /tmp/glymur-cycle-$name)"
}

cycle rtc "Suspending now; the RTC alarm wakes it in about 40 s. If it is still asleep after 90 s, press the power button."
cycle lid "Close the lid now, wait 20 s, then open it."
cycle button "Suspending in 3 s; wait 20 s, then press the power button briefly."

sect result
ok=1
for c in rtc lid button; do
    printf '%s: %s\n' "$c" "$(cat /tmp/glymur-cycle-$c)"
    [ "$(cat /tmp/glymur-cycle-$c)" = y ] || ok=0
done
systemctl disable glymur-suspend-guard.service >/dev/null 2>&1
rm -f "$GUARD"
systemctl daemon-reload
if [ "$ok" = 1 ] && [ "$(ask 'Keep suspend enabled (lid close suspends from now on)? [y/N]')" = y ]; then
    echo 'suspend stays unmasked'
else
    systemctl mask $TARGETS
    echo 'suspend masked again'
fi
echo "log: $OUT"
