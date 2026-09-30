#!/usr/bin/env bash
set -u

# Watch USB-C charging live; type notes, q to stop. See README.md.
#   sudo bash charging-watch.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
[ -d /sys/firmware/devicetree/base ] || { echo 'not a device-tree boot' >&2; exit 1; }
OUT="/var/log/glymur/charging-watch-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec 3>>"$OUT"
log() { printf '%s %s\n' "$(date +%T.%3N)" "$*" >&3; }
say() { log "$*"; printf '%s\n' "$*"; }

mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
T=/sys/kernel/tracing
mountpoint -q "$T" || mount -t tracefs none "$T"
DD=/sys/kernel/debug/dynamic_debug/control
MODS="ucsi_glink typec_ucsi pmic_glink qcom_battmgr pmic_glink_altmode"

# Readers run as their own process groups; cleanup kills the groups.
set -m
READERS=()
cleanup() {
    trap - EXIT HUP INT TERM
    [ -e "$T/events/ucsi/enable" ] && echo 0 > "$T/events/ucsi/enable"
    for m in $MODS; do echo "module $m -p" > "$DD" 2>/dev/null; done
    for g in "${READERS[@]}"; do kill -- "-$g" 2>/dev/null; done
    sync
    echo; echo "Saved to $OUT"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

say "charging-watch on $(uname -r), $(tr -d '\0' < /sys/firmware/devicetree/base/model)"
say "cmdline: $(sed 's/root=[^ ]*/root=…/' /proc/cmdline)"
for m in $MODS; do echo "module $m +p" > "$DD" 2>/dev/null || say "no dynamic debug for $m"; done
if [ -e "$T/events/ucsi/enable" ]; then
    echo > "$T/trace"; echo 1 > "$T/events/ucsi/enable"
    (while IFS= read -r l; do log "TRACE $l"; done < "$T/trace_pipe") </dev/null &
    READERS+=("$!")
else
    say 'no ucsi tracepoints (typec_ucsi not loaded?)'
fi
(journalctl -k -f -n 0 --no-pager -o short-monotonic | while IFS= read -r l; do log "KERN $l"; done) </dev/null &
READERS+=("$!")
(while kill -0 $$ 2>/dev/null; do sleep 2; done
 for g in "${READERS[@]}"; do kill -- "-$g" 2>/dev/null; done) </dev/null >/dev/null 2>&1 &

UD="$(ls -d /sys/kernel/debug/usb/ucsi/*/ 2>/dev/null | head -1)"
[ -n "$UD" ] || say 'no UCSI debugfs directory; firmware connector status not polled'
# GET_CONNECTOR_STATUS: opmode 16-18, connected 19, direction 20, partner 29-31.
constat() {
    local c="$1" r lo
    echo "$(( 0x12 | (c << 16) ))" > "$UD/command" 2>/dev/null || { echo "con$c:cmd-failed"; return; }
    r="$(cat "$UD/response" 2>/dev/null)" || { echo "con$c:resp-failed"; return; }
    lo=$(( 0x${r: -8} ))
    printf 'con%d:conn=%d opmode=%d dir=%d partner=%d' "$c" \
        $(( (lo >> 19) & 1 )) $(( (lo >> 16) & 7 )) $(( (lo >> 20) & 1 )) $(( (lo >> 29) & 7 ))
}
rd() { cat "$1" 2>/dev/null || echo -; }
state() {
    local s="" p q
    for p in /sys/class/typec/port?; do
        q="${p##*/}"
        s+="$q:$(rd "$p/power_operation_mode")"
        [ -d "$p/$q-partner" ] && s+="+partner"
        s+=" "
    done
    for p in /sys/class/power_supply/ucsi-source-psy-*; do
        s+="${p##*.}:on=$(rd "$p/online"),$(sed 's/.*\[\(.*\)\].*/\1/' "$p/usb_type" 2>/dev/null),$(rd "$p/current_now")uA "
    done
    s+="ac=$(rd /sys/class/power_supply/qcom-battmgr-ac/online) usb=$(rd /sys/class/power_supply/qcom-battmgr-usb/online) "
    s+="bat=$(rd /sys/class/power_supply/qcom-battmgr-bat/status)"
    printf '%s' "$s"
}

say 'Watching. Type notes + Enter (e.g. "unplugged", "LED on"); q + Enter to stop.'
last="" lastfw="" beat=0 fwt=0
while :; do
    if read -r -t 0.5 note; then
        [ "$note" = q ] && break
        say "NOTE $note"
    fi
    now="$(state)"
    [ "$now" != "$last" ] && { say "STATE $now"; last="$now"; }
    if [ -n "$UD" ] && [ $(( SECONDS - fwt )) -ge 2 ]; then
        fwt=$SECONDS
        fw="$(constat 1) $(constat 2)"
        [ "$fw" != "$lastfw" ] && { say "FW $fw"; lastfw="$fw"; }
    fi
    if [ $(( SECONDS - beat )) -ge 30 ]; then
        beat=$SECONDS
        log "BEAT bat_power_uW=$(rd /sys/class/power_supply/qcom-battmgr-bat/power_now) capacity=$(rd /sys/class/power_supply/qcom-battmgr-bat/capacity)"
    fi
done
