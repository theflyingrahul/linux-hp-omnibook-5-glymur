#!/usr/bin/env bash
set -u

# Which EC register carries hotkey events? HP's AML reads the event through a
# field that starts at offset 0, so register 0x00; the driver uses 0x05. With
# the driver unbound, this waits for each falling edge on GPIO 66, reads
# registers 0x00 and 0x05 at once, and acknowledges register 0x00 with a 0 as
# HP's AML does. Press the asked-for key, then Enter.
#   sudo bash ec-event-capture.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
BUS=9; ADDR=0x76; CHIP=gpiochip0; PIN=66
DRV=/sys/bus/i2c/drivers/hp-omnibook-5-ec
OUT="/var/log/glymur/ec-events-$(date +%Y%m%dT%H%M%S).txt"
EDGES="$(mktemp)"
mkdir -p /var/log/glymur
cleanup() {
    kill "${W:-0}" 2>/dev/null; wait "${W:-0}" 2>/dev/null
    pkill -f "gpiomon --chip $CHIP" 2>/dev/null
    [ -e $DRV/$BUS-0076 ] || echo "$BUS-0076" > $DRV/bind 2>/dev/null
    sleep 1
    echo audio-mute > /sys/class/leds/platform::mute/trigger 2>/dev/null
    echo audio-micmute > /sys/class/leds/platform::micmute/trigger 2>/dev/null
    echo "driver rebound: $(ls $DRV | grep -c "$BUS-0076")" | tee -a "$OUT"
    rm -f "$EDGES"
}
trap cleanup EXIT

{
    echo "kernel: $(uname -r)"
    echo "reg00 before: $(i2cget -y $BUS $ADDR 0x00 2>&1) (driver bound, may be busy)"
} | tee "$OUT"
echo "$BUS-0076" > $DRV/unbind
sleep 0.5
echo "unbound; reg00=$(i2cget -y $BUS $ADDR 0x00) reg05=$(i2cget -y $BUS $ADDR 0x05)" | tee -a "$OUT"
i2cset -y $BUS $ADDR 0x00 0x00 && echo "acknowledged register 0x00 (wrote 0)" | tee -a "$OUT"

# (pass 2 is optional)
# one line per falling edge: time, reg00, reg05; a non-zero reg00 is acknowledged
(
    stdbuf -oL gpiomon --chip $CHIP --edges falling $PIN 2>/dev/null | while read -r _; do
        a=$(i2cget -y $BUS $ADDR 0x00 2>&1); b=$(i2cget -y $BUS $ADDR 0x05 2>&1)
        echo "$(date +%T.%N | cut -c1-12) edge: reg00=$a reg05=$b" >> "$EDGES"
        [ "$a" != 0x00 ] && i2cset -y $BUS $ADDR 0x00 0x00 2>/dev/null
    done
) &
W=$!
sleep 1
echo "line quiet check: $(wc -l < "$EDGES") edges in the first second" | tee -a "$OUT"

keys() {
    for key in "F9 (microphone mute)" "F9 (microphone mute)" "F11" "F6 (speaker mute)" "F5 (keyboard backlight)" "Fn alone"; do
        n=$(wc -l < "$EDGES")
        read -r -p "Press $key ONCE, then press Enter: " _ </dev/tty
        sleep 0.7
        got="$(tail -n +$((n + 1)) "$EDGES" | sed 's/^/    /')"
        echo "$key -> $(printf '%s' "$got" | grep -c .) edge(s)" | tee -a "$OUT"
        [ -n "$got" ] && printf '%s\n' "$got" | tee -a "$OUT"
    done
}

echo "== pass 1: events as the EC is" | tee -a "$OUT"
keys

read -r -p "Second pass with the reference 'enable SCI events' command (write 1 to register 0x35, written back to 0 at the end)? y/N: " yn </dev/tty
if [ "$yn" = y ]; then
    i2cset -y $BUS $ADDR 0x35 0x01 && echo "== pass 2: register 0x35 set to 1" | tee -a "$OUT"
    keys
    i2cset -y $BUS $ADDR 0x35 0x00 && echo "register 0x35 back to 0" | tee -a "$OUT"
fi
echo "Saved to $OUT"
