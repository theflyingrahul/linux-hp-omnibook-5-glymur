#!/usr/bin/env bash
set -u

# EC report, kernel -9 on; the event line needs the test device tree.
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

sect "kernel warnings and errors, in full"
journalctl -k -b --no-pager -o short-monotonic |
    awk '/-+\[ cut here \]-+|WARNING:|BUG:|Oops|Unable to handle/ { n = 45 }
         n > 0 { print; n-- }' | tail -400

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

# The EC runs the keyboard backlight (F5); the driver sets only its timeout.
sect "keyboard backlight timeout"
T=
[ -n "$BUS" ] && T=/sys/bus/i2c/devices/${BUS}-0076/kbd_backlight_timeout
if [ -n "$T" ] && [ -e "$T" ]; then
    old=$(cat "$T")
    echo "timeout now: $old (Windows: 30 sec, 3 min, Always)"
    for v in 30s always; do
        echo "$v" > "$T"
        echo "set $v, reads back $(cat "$T")"
        echo "Turn the backlight on with F5, then keep off the keyboard and touchpad for 45 s."
        sleep 50
        ask "After 45 s untouched with '$v': is the backlight on or off?"
    done
    echo "$old" > "$T"
    echo "restored: $(cat "$T")"
else
    echo "no kbd_backlight_timeout attribute"
fi

# Read-only from -11: only F5 changes the level, inside the EC.
sect "keyboard backlight level"
L=
[ -n "$BUS" ] && L=/sys/bus/i2c/devices/${BUS}-0076/kbd_backlight_level
if [ -n "$L" ] && [ -e "$L" ]; then
    echo "level now: $(cat "$L")"
    for i in 1 2 3; do
        ask "Press F5 once (press $i of 3), then Enter. Is the backlight off, dim or bright?"
        echo "level reads: $(cat "$L")"
    done
else
    echo "no kbd_backlight_level attribute"
fi

# EC LED 8 is taken as F6 (speaker mute) and 9 as F9 (mic mute). Start
# from a known state: the EC may already have an LED on.
sect "mute LEDs"
declare -A was
for n in mute micmute; do
    L=/sys/class/leds/platform::$n
    [ -e "$L" ] || { echo "no platform::$n LED"; continue; }
    was[$n]=$(cat $L/brightness)
    echo "platform::$n reads ${was[$n]}"
done
if [ ${#was[@]} -eq 2 ]; then
    ask "In the last Windows session, were the speakers or the microphone muted (speaker, mic, both, none, unsure)? Was this boot a restart from Windows, or from power off?"
    ask "Before any change, which key LEDs are lit: F6, F9, both or none?"
    for n in mute micmute; do echo 0 > /sys/class/leds/platform::$n/brightness; done
    sleep 0.5
    echo "both off, read back: mute $(cat /sys/class/leds/platform::mute/brightness), micmute $(cat /sys/class/leds/platform::micmute/brightness)"
    ask "Both set off. Which are lit now: F6, F9, both or none?"
    for n in mute micmute; do
        L=/sys/class/leds/platform::$n
        echo 1 > $L/brightness
        sleep 0.5
        echo "platform::$n on, read back: mute $(cat /sys/class/leds/platform::mute/brightness), micmute $(cat /sys/class/leds/platform::micmute/brightness)"
        ask "Only platform::$n set on. Which are lit now: F6, F9, both or none?"
        echo 0 > $L/brightness
    done
    for n in mute micmute; do echo "${was[$n]}" > /sys/class/leds/platform::$n/brightness; done
    sleep 0.5
    echo "restored: mute $(cat /sys/class/leds/platform::mute/brightness), micmute $(cat /sys/class/leds/platform::micmute/brightness)"
fi

# F9 sends a HID Mute as well as its EC event; the timestamps show the order.
sect "EC event line before the capture"
grep -E 'hp-omnibook-5-ec' /proc/interrupts || echo "no hp-omnibook-5-ec interrupt"
D=/sys/kernel/debug
grep -E 'gpio66[^0-9]|pin 66 ' "$D"/gpio "$D"/pinctrl/*/pinconf-pins 2>/dev/null
sect "hotkeys (30 s capture)"
# The event bytes the driver reads from EC register 0x05, from -12 on.
TR=/sys/kernel/tracing
EV=$TR/events/smbus/smbus_reply
if [ -n "$BUS" ] && [ -d "$EV" ]; then
    echo 0 > $TR/tracing_on; : > $TR/trace
    echo "adapter_nr == $BUS && command == 5" > $EV/filter
    echo 1 > $EV/enable; echo 1 > $TR/tracing_on
fi
echo "Press, slowly and in order: F6, F9, F11, F5, then Fn alone (Fn lock)."
python3 - <<'PY'
import os, re, select, struct, time
want = ("Keyboard", "Consumer Control", "EC hotkeys", "gpio-keys")
fds = {}
for block in open("/proc/bus/input/devices").read().split(chr(10) * 2):
    name = re.search(r'N: Name="([^"]*)"', block)
    ev = re.search(r"H: Handlers=.*?(event\d+)", block)
    if name and ev and any(w in name.group(1) for w in want):
        try:
            fds[os.open("/dev/input/" + ev.group(1), os.O_RDONLY)] = name.group(1)
        except OSError as e:
            print("cannot open", ev.group(1), e)
print("devices:", sorted(set(fds.values())), flush=True)
fmt = "llHHi"; size = struct.calcsize(fmt)
end = time.time() + 30
while time.time() < end:
    for fd in select.select(list(fds), [], [], 1.0)[0]:
        data = os.read(fd, size * 16)
        for i in range(0, len(data) - size + 1, size):
            sec, usec, typ, code, val = struct.unpack(fmt, data[i:i + size])
            if typ in (1, 4):
                print(f"{sec}.{usec:06d} {fds[fd]}: {'KEY' if typ == 1 else 'MSC'} code={code} value={val}", flush=True)
print("capture done", flush=True)
PY
journalctl -k -b --no-pager | grep -i 'hp-omnibook-5-ec' | tail -20
echo "interrupts after: $(grep -E 'hp-omnibook-5-ec' /proc/interrupts || echo none)"
if [ -d "${EV:-/nonexistent}" ]; then
    echo 0 > $TR/tracing_on; echo 0 > $EV/enable; echo 0 > $EV/filter
    echo "EC event bytes read during the capture (count, byte):"
    grep smbus_reply $TR/trace | grep -o '\[[0-9a-f-]*\]$' | sort | uniq -c
    echo "first and last reads, with times:"
    grep smbus_reply $TR/trace | sed -n '1,5p;$p'
    : > $TR/trace
fi

# Read only. Its vendor collection (usage page 0xff85, usage 0x68 on
# Windows) is a candidate for a backlight level control.
sect "keyboard HID report descriptor"
for h in /sys/bus/hid/devices/*:0416:C300.*; do
    [ -e "$h/report_descriptor" ] || continue
    echo "$h"
    od -An -tx1 -v "$h/report_descriptor"
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
