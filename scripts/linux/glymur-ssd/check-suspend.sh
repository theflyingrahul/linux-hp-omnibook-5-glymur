#!/usr/bin/env bash
set -u

# Supervised s2idle test (kernel -20 on). See README.md.
#   sudo bash check-suspend.sh [--sync-state] [--deep]
# s2idle only, unless --deep: the firmware refuses PSCI system suspend
# (-95), so every "deep" attempt takes the CPUs offline, fails and falls back.
# Three suspend cycles: woken by an RTC alarm, by opening the lid (the
# charger replugged while asleep), by the power button; then a fourth, not
# gating, lid closed on AC for 2 minutes. Each logs its wake IRQ. Each resume records what came back. Suspend stays unmasked
# only if you say so at the end, after every cycle resumed; if a resume
# hangs and the laptop is powered off, a one-shot unit masks it again at
# the next boot.
# --sync-state first releases the providers still waiting for sync_state
# (the clocks held by the unbound GPU management unit), whose boot votes
# otherwise keep DDR and the SoC rails up in suspend.

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
SYNC=0
DEEP=0
for a in "$@"; do
    [ "$a" = --sync-state ] && SYNC=1
    [ "$a" = --deep ] && DEEP=1
done
OUT="/var/log/glymur/suspend-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
redact() {
    sed -u -E -e 's/\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b/xx:xx:xx:xx:xx:xx/g' \
        -e 's/\b[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b/<uuid>/g' \
        -e 's/(SSID|ssid)[ :=]+.*/\1 <ssid>/'
}
exec 3>/dev/tty 2>/dev/null || exec 3>&2
exec > >(redact | tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }
# The question goes straight to the terminal (the log pipe only passes whole
# lines, so a prompt sent through it shows up after the answer). Keys pressed
# while it slept are thrown away first. The answer is left in $REPLY.
ask() {
    while read -r -t 0.05 -n 4096 _ </dev/tty 2>/dev/null; do :; done
    printf '\n%s ' "$1" >&3
    read -r REPLY </dev/tty
    printf '  Q: %s\n  A: %s\n' "$1" "$REPLY"
}
TARGETS="sleep.target suspend.target"

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo
sed 's/root=[^ ]*/root=…/' /proc/cmdline
# From -20 the EC driver tells the EC about standby; its events and any
# "cannot tell the EC" warning land in each cycle's kernel log.
echo 'module hp_omnibook_5_ec +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null &&
    echo "EC event logging on" || echo "EC event logging not available"
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
    echo "network: $(nmcli -t -f STATE,CONNECTIVITY general 2>&1)"
    aplay -l 2>&1 | grep -E '^card'
    for p in /sys/class/power_supply/*; do
        printf '%s: %s %s\n' "${p##*/}" "$(cat "$p/status" 2>/dev/null)" "$(cat "$p/capacity" 2>/dev/null)"
    done
    for c in /sys/class/drm/card*-*; do
        printf '%s: %s %s\n' "${c##*/}" "$(cat "$c/status" 2>/dev/null)" "$(cat "$c/enabled" 2>/dev/null)"
    done
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat "$h/name" 2>/dev/null)" = hp_omnibook_ec ] || continue
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
ask 'Continue? (y/n)'
[ "$REPLY" = y ] || { echo stopped; exit 0; }
MEM_SLEEP_WAS=$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/power/mem_sleep)
if [ "$DEEP" = 0 ] && grep -q s2idle /sys/power/mem_sleep; then
    echo s2idle > /sys/power/mem_sleep
    echo "mem_sleep set to s2idle (was $MEM_SLEEP_WAS): $(cat /sys/power/mem_sleep)"
fi
# Log every device's suspend and resume step, so a hang names its device.
PMDBG=$(cat /sys/power/pm_debug_messages 2>/dev/null)
PMPT=$(cat /sys/power/pm_print_times 2>/dev/null)
echo 1 > /sys/power/pm_debug_messages 2>/dev/null
echo 1 > /sys/power/pm_print_times 2>/dev/null
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
    echo "While it sleeps, look at: the fan, the keyboard backlight, the power LED. You are asked afterwards."
    sync
    journalctl --sync 2>/dev/null
    logger -t check-suspend "cycle $name: suspending now"
    if [ "$name" = rtc ]; then
        rtcwake -d rtc0 -m no -s 40 2>&1 || echo 'No RTC alarm (the RTC has no time source): wake it yourself after 20 s with a key or the touchpad.'
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
    w=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
    echo "wake IRQ: ${w:-none}${w:+ ($(awk -v i="$w:" '$1 == i {$1 = ""; print}' /proc/interrupts | tr -s ' ' | cut -c1-120))}"
    sect "kernel log of the cycle"
    journalctl -k --no-pager --since "@$t0" -o short-monotonic | tail -250
    devices "after $name"
    snapshot "after $name"
    echo
    ask "Cycle $name: fan while it slept? (on / off / unsure)"
    ask "Cycle $name: keyboard backlight while it slept? (on / off / unsure)"
    ask "Cycle $name: power LED while it slept? (steady / breathing / off / unsure)"
    ask "Cycle $name: did the screen come back? (y / n)"; screen=$REPLY
    ask "Cycle $name: did the keyboard and touchpad work after? (y / n)"; input=$REPLY
    ask "Cycle $name: USB mouse moves the pointer? (y / n / none plugged in)"
    ask "Cycle $name: Wi-Fi back, a web page loads? (y / n / unsure)"
    [ "$screen" = y ] && [ "$input" = y ] && echo y > /tmp/glymur-cycle-$name || echo n > /tmp/glymur-cycle-$name
    echo "owner: $(cat /tmp/glymur-cycle-$name)"
}

cycle rtc "Suspending now; the RTC alarm wakes it in about 40 s. If it is still asleep after 90 s, press the power button."
cycle lid "Close the lid now. While it sleeps, unplug the charger, wait 10 s, plug it back in, wait 10 s more, then open the lid."
cycle button "Suspending in 3 s; wait 20 s, then press the power button briefly."
# Not gating: on the Zenbook A16 the lid line pulses once in deep sleep on
# AC and wakes it; a short "resumed after" here shows the same.
cycle lid-ac "With the charger plugged in, close the lid and leave it closed for 2 minutes, then open it."

sect result
ok=1
for c in rtc lid button; do
    printf '%s: %s\n' "$c" "$(cat /tmp/glymur-cycle-$c)"
    [ "$(cat /tmp/glymur-cycle-$c)" = y ] || ok=0
done
systemctl disable glymur-suspend-guard.service >/dev/null 2>&1
rm -f "$GUARD"
systemctl daemon-reload
[ -n "$PMDBG" ] && echo "$PMDBG" > /sys/power/pm_debug_messages
[ -n "$PMPT" ] && echo "$PMPT" > /sys/power/pm_print_times
[ -n "${MEM_SLEEP_WAS:-}" ] && echo "$MEM_SLEEP_WAS" > /sys/power/mem_sleep 2>/dev/null
KEEP=n
if [ "$ok" = 1 ]; then ask 'Keep suspend enabled (lid close suspends from now on)? (y / n)'; KEEP=$REPLY; fi
if [ "$KEEP" = y ]; then
    echo 'suspend stays unmasked'
else
    systemctl mask $TARGETS
    echo 'suspend masked again'
fi
echo "log: $OUT"
