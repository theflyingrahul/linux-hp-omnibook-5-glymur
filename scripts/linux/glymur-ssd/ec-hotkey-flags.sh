#!/usr/bin/env bash
set -u

# Does an EC OS-state flag switch on hotkey events? HP's AML has methods
# APET (flag 0x80) and SCET (0x81) that nothing in the tables calls: HP's
# Windows driver does. Sets each flag with the driver unbound, watches EC
# register 0x05 while F9 and F11 are pressed, then clears the flag again.
# See docs/runbook-results-16-2026-10-21.md.
#   sudo bash ec-hotkey-flags.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
BUS=9; ADDR=0x76
DRV=/sys/bus/i2c/drivers/hp-omnibook-5-ec
OUT="/var/log/glymur/ec-flags-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
U="${SUDO_USER:-rahul}"; XR="/run/user/$(id -u "$U")"
note() {
    sudo -u "$U" XDG_RUNTIME_DIR="$XR" DBUS_SESSION_BUS_ADDRESS="unix:path=$XR/bus" \
        notify-send -u critical -t 9000 "$1" "$2" 2>/dev/null
    echo "== $1: $2" | tee -a "$OUT"
}

st() { i2ctransfer -y $BUS w1@$ADDR 0xef r1 2>&1; }
# the driver's hpec_command(): wait for idle, write cmd+sub to 0xed, wait for done
cmd() {
    local i
    for i in $(seq 1 20); do [ "$(st)" = 0x00 ] && break; sleep 0.005; done
    i2ctransfer -y $BUS w3@$ADDR 0xed "$1" "$2" 2>&1 || return 1
    for i in $(seq 1 20); do [ "$(st)" = 0xe0 ] && { echo "cmd $1 $2: done"; return 0; }; sleep 0.005; done
    echo "cmd $1 $2: status $(st) (no 0xe0)"
}
cleanup() {
    cmd 0x01 0x00 >> "$OUT" 2>&1; cmd 0x01 0x01 >> "$OUT" 2>&1
    [ -e $DRV/$BUS-0076 ] || echo "$BUS-0076" > $DRV/bind 2>/dev/null
    sleep 1
    # a new LED device starts without the audio triggers
    echo audio-mute > /sys/class/leds/platform::mute/trigger 2>/dev/null
    echo audio-micmute > /sys/class/leds/platform::micmute/trigger 2>/dev/null
    echo "driver rebound: $(ls $DRV | grep -c "$BUS-0076"), flags cleared" | tee -a "$OUT"
}
trap cleanup EXIT

{ echo "kernel: $(uname -r)"; echo "EC register 0x05 before: $(i2cget -y $BUS $ADDR 0x05 2>&1)"; } | tee "$OUT"
echo "$BUS-0076" > $DRV/unbind
sleep 0.5

trial() {  # name, then the cmd sub pairs to set
    local name=$1; shift
    note "Trial: $name" "In 3 s press F9 twice, then F11 twice (20 s window)"
    sleep 3
    while [ $# -gt 1 ]; do cmd "$1" "$2" | tee -a "$OUT"; shift 2; done
    local end=$((SECONDS + 20)) last="" v seen=0
    note "PRESS NOW ($name)" "F9 twice, then F11 twice"
    while [ $SECONDS -lt $end ]; do
        v=$(i2cget -y $BUS $ADDR 0x05 2>&1)
        if [ "$v" != "0x00" ] && [ "$v" != "$last" ]; then
            echo "$(date +%T.%N | cut -c1-12) reg05 = $v" | tee -a "$OUT"; seen=$((seen + 1))
            i2cset -y $BUS $ADDR 0x05 0x00 2>/dev/null   # acknowledge, as HP's AML does
        fi
        last=$v
        sleep 0.03
    done
    echo "$name: $seen non-zero reads of register 0x05" | tee -a "$OUT"
}

trial "no flag set (baseline)"
trial "APET 0x80" 0x01 0x80
cmd 0x01 0x00 | tee -a "$OUT"
trial "SCET 0x81" 0x01 0x81
cmd 0x01 0x01 | tee -a "$OUT"
trial "APET and SCET together" 0x01 0x80 0x01 0x81
note "Finished" "flags cleared, driver rebound"
