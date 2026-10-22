#!/usr/bin/env bash
set -u

# Does an EC OS-state flag switch on hotkey events? HP's AML has methods
# APET (flag 0x80) and SCET (0x81) that nothing in the tables calls: HP's
# Windows driver does. Sets each flag with the driver unbound, watches EC
# register 0x00 (the event register, HP's IC10.INTR) while F9 and F11 are
# pressed, then clears the flag again.
# This WRITES the EC's OS-state flags (mailbox command 0x01, HP's own
# encoding: 0x80/0x81 set, 0x00/0x01 clear). They persist in the EC until a
# BIOS reset, and they cannot be read back. Run it only with the owner's
# go-ahead. Flag 0x80 (APET) is the action-keys mode: clearing it turns
# F1-F12 into plain function keys, so the script leaves it set at the end;
# 0x81 (SCET) ends cleared. The 2026-10-22 run watched register 0x05 and
# its result is void (docs/audit-2026-10-22.md).
#   sudo bash ec-hotkey-flags.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
read -r -p "This writes persistent EC flags (see the header). Type 'write EC flags' to go on: " ok </dev/tty
[ "$ok" = "write EC flags" ] || { echo 'nothing written'; exit 1; }
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
    cmd 0x01 0x80 >> "$OUT" 2>&1
    [ -e $DRV/$BUS-0076 ] || echo "$BUS-0076" > $DRV/bind 2>/dev/null
    sleep 1
    # a new LED device starts without the audio triggers
    echo audio-mute > /sys/class/leds/platform::mute/trigger 2>/dev/null
    echo audio-micmute > /sys/class/leds/platform::micmute/trigger 2>/dev/null
    echo "driver rebound: $(ls $DRV | grep -c "$BUS-0076"), flags cleared" | tee -a "$OUT"
}
trap cleanup EXIT

{ echo "kernel: $(uname -r)"; echo "EC register 0x00 before: $(i2cget -y $BUS $ADDR 0x00 2>&1)"; } | tee "$OUT"
echo "$BUS-0076" > $DRV/unbind
sleep 0.5
# A pending event holds the line; acknowledge it as HP's AML does.
echo "pending event: $(i2cget -y $BUS $ADDR 0x00 2>&1)" | tee -a "$OUT"
i2cset -y $BUS $ADDR 0x00 0x00 && echo "acknowledged register 0x00" | tee -a "$OUT"

trial() {  # name, then the cmd sub pairs to set
    local name=$1; shift
    note "Trial: $name" "In 3 s press F9 twice, then F11 twice (20 s window)"
    sleep 3
    while [ $# -gt 1 ]; do cmd "$1" "$2" | tee -a "$OUT"; shift 2; done
    local end=$((SECONDS + 20)) last="" v seen=0
    note "PRESS NOW ($name)" "F9 twice, then F11 twice"
    while [ $SECONDS -lt $end ]; do
        v=$(i2cget -y $BUS $ADDR 0x00 2>&1)
        if [ "$v" != "0x00" ] && [ "$v" != "$last" ]; then
            echo "$(date +%T.%N | cut -c1-12) reg00 = $v" | tee -a "$OUT"; seen=$((seen + 1))
            i2cset -y $BUS $ADDR 0x00 0x00 2>/dev/null   # acknowledge, as HP's AML does
        fi
        last=$v
        sleep 0.03
    done
    echo "$name: $seen non-zero reads of register 0x00" | tee -a "$OUT"
}

trial "no flag set (baseline)"
trial "APET 0x80" 0x01 0x80
cmd 0x01 0x80 | tee -a "$OUT"
trial "SCET 0x81" 0x01 0x81
cmd 0x01 0x01 | tee -a "$OUT"
trial "APET and SCET together" 0x01 0x80 0x01 0x81
note "Finished" "flags cleared, driver rebound"
