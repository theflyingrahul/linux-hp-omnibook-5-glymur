#!/usr/bin/env bash
set -u

# EC report for the "device tree (GPU and USB-A test)" boot, kernel -9 on.
# See README.md.
#   sudo bash check-ec.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/ec-test-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
exec > >(tee "$OUT") 2>&1
sect() { printf '\n==== %s\n' "$*"; }

sect system
uname -r
tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null; echo

sect "kernel log: EC bus and driver"
journalctl -k -b --no-pager |
    grep -iE 'a84000|i2c9|gpi|geni|hp-omnibook|hp_omnibook|embedded-controller|0-0076|-0076' | tail -60

sect "EC device and driver"
BUS=
for a in /sys/bus/i2c/devices/i2c-*; do
    readlink -f "$a" | grep -q 'a84000' && BUS=${a##*i2c-}
done
echo "i2c bus for a84000: ${BUS:-none}"
EC=/sys/bus/i2c/devices/${BUS}-0076
if [ -n "$BUS" ] && [ -e "$EC" ]; then
    echo "client: $EC"
    echo "driver: $(basename "$(readlink -f "$EC/driver" 2>/dev/null)" 2>/dev/null)"
fi
lsmod | grep -E 'hp_omnibook_5_ec|i2c_qcom_geni|gpi' || true

sect "hwmon (5 samples, 2 s apart)"
HW=
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = hp_omnibook_ec ] && HW=$h
done
if [ -n "$HW" ]; then
    for i in 1 2 3 4 5; do
        line="fan1 $(cat "$HW/fan1_input" 2>&1) rpm"
        for t in "$HW"/temp*_input; do
            line+=" | $(cat "${t%_input}_label" 2>/dev/null): $(cat "$t" 2>&1)"
        done
        echo "$line"
        sleep 2
    done
else
    echo "no hp_omnibook_ec hwmon device"
fi

ask() { local a; read -r -p "$1 " a </dev/tty; echo "answer: $a"; }

sect "keyboard backlight LED"
L=/sys/class/leds/hp::kbd_backlight
if [ -e "$L" ]; then
    old=$(cat $L/brightness)
    echo "brightness $old of $(cat $L/max_brightness)"
    for b in 0 1 2; do
        echo "$b" > $L/brightness
        echo "set $b, reads back $(cat $L/brightness)"
        ask "Keyboard backlight now: off, dim or bright?"
    done
    echo "$old" > $L/brightness
else
    echo "no hp::kbd_backlight LED"
fi

# Which EC LED is the F6 (speaker mute) and which the F9 (mic mute) LED
# is not known yet.
sect "mute LEDs"
for n in mute micmute; do
    L=/sys/class/leds/platform::$n
    [ -e "$L" ] || { echo "no platform::$n LED"; continue; }
    echo "platform::$n reads $(cat $L/brightness)"
    echo 1 > $L/brightness
    echo "platform::$n on, reads back $(cat $L/brightness)"
    ask "Which key LED is lit now: F6, F9, both or none?"
    echo 0 > $L/brightness
    echo "platform::$n off, reads back $(cat $L/brightness)"
done

# Only when the driver did not bind: HP's own read commands, by hand.
sect "manual mailbox probe (only without the driver)"
if [ -n "$HW" ]; then
    echo "skipped: the driver is bound"
elif [ -z "$BUS" ]; then
    echo "skipped: no i2c bus for a84000"
elif ! command -v i2ctransfer >/dev/null; then
    echo "skipped: i2ctransfer missing (apt install i2c-tools)"
else
    status() { i2ctransfer -y "$BUS" w1@0x76 0xef r1@0x76; }
    wait_for() {
        for _ in $(seq 20); do
            s=$(status 2>&1) || { echo "status read failed: $s"; return 1; }
            [ "$s" = "$1" ] && return 0
            sleep 0.005
        done
        echo "status stayed $s, wanted $1"; return 1
    }
    mailbox() {
        echo "-- command $1 $2"
        wait_for 0x00 || return
        i2ctransfer -y "$BUS" w3@0x76 0xed "$1" "$2" || return
        wait_for 0xe0 || return
        i2ctransfer -y "$BUS" w1@0x76 0xee r32@0x76
    }
    echo "status: $(status 2>&1)"
    mailbox 0xbc 0x03
    for s in 0x00 0x07 0x04 0x0a; do mailbox 0x26 "$s"; done
    mailbox 0x05 0xff
    mailbox 0x06 0xff
    echo "-- who am I (0x43): $(i2ctransfer -y "$BUS" w1@0x76 0x43 r1@0x76 2>&1)"
    echo "-- capabilities (0x44): $(i2ctransfer -y "$BUS" w1@0x76 0x44 r6@0x76 2>&1)"
fi

echo
echo "saved to $OUT"
