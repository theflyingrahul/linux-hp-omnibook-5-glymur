#!/usr/bin/env bash
set -u

# Which input events does each special key send? One key at a time: press
# the key when asked, then Enter. See README.md.
#   sudo bash check-hotkeys.sh

[ "$(id -u)" -eq 0 ] || { echo 'run with sudo' >&2; exit 1; }
OUT="/var/log/glymur/hotkeys-$(date +%Y%m%dT%H%M%S).txt"
mkdir -p /var/log/glymur
TMP="$(mktemp)"
trap 'rm -f "$TMP" "$TMP.py"; kill "${CAP:-0}" 2>/dev/null' EXIT

cat > "$TMP.py" <<'PY'
import glob, os, select, struct, sys, time
fds = {}
for d in sorted(glob.glob('/sys/class/input/event*')):
    n = open(d + '/device/name').read().strip()
    if any(k in n for k in ('Keyboard', 'Consumer', 'EC hotkeys', 'gpio-keys')):
        fds[os.open('/dev/input/' + os.path.basename(d), os.O_RDONLY)] = n.replace('hid-over-i2c ', '')
NAMES = {1: 'Esc', 28: 'Enter', 29: 'LCtrl', 42: 'LShift', 56: 'LAlt', 125: 'Meta', 113: 'MUTE', 114: 'VOLUMEDOWN',
         115: 'VOLUMEUP', 164: 'PLAYPAUSE', 163: 'NEXTSONG', 165: 'PREVIOUSSONG', 248: 'MICMUTE', 224: 'BRIGHTNESSDOWN',
         225: 'BRIGHTNESSUP', 142: 'SLEEP', 143: 'WAKEUP', 148: 'PROG1', 149: 'PROG2', 140: 'CALC', 150: 'WWW',
         152: 'COFFEE', 155: 'MAIL', 172: 'HOMEPAGE', 171: 'CONFIG', 190: 'F20', 193: 'F23', 187: 'F17',
         240: 'UNKNOWN', 247: 'RFKILL', 238: 'WLAN', 237: 'BLUETOOTH', 522: 'WWAN', 372: 'ZOOM', 183: 'F13',
         184: 'F14', 185: 'F15', 186: 'F16', 188: 'F18', 189: 'F19', 191: 'F21', 192: 'F22', 194: 'F24',
         88: 'F12', 87: 'F11', 68: 'F10', 67: 'F9', 66: 'F8', 65: 'F7', 64: 'F6', 63: 'F5', 62: 'F4', 61: 'F3',
         60: 'F2', 59: 'F1', 99: 'SYSRQ', 107: 'END', 110: 'INSERT', 111: 'DELETE', 70: 'SCROLLLOCK',
         119: 'PAUSE', 127: 'COMPOSE', 464: 'FN', 465: 'FN_ESC', 466: 'FN_F1', 471: 'FN_F6', 472: 'FN_F7'}
F = 'llHHi'; Z = struct.calcsize(F)
while True:
    r, _, _ = select.select(list(fds), [], [], 1)
    for fd in r:
        b = os.read(fd, Z * 16)
        for i in range(0, len(b) - Z + 1, Z):
            s, u, t, c, v = struct.unpack(F, b[i:i + Z])
            if t == 1 and v != 2:
                print('%.3f %s %s(%d) %s' % (time.time(), fds[fd], NAMES.get(c, '?'), c, 'down' if v else 'up'), flush=True)
PY

{
    echo "kernel: $(uname -r)"
    echo "Each step: the key events the kernel saw, as device name(code). Passes:"
    echo "F1-F12 on their own, then F1-F12 with Fn held, then Fn alone and the Copilot key."
} | tee "$OUT"

keys=()
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do keys+=("F$n on its own"); done
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do keys+=("Fn held together with F$n"); done
keys+=("Fn alone" "Copilot key")
echo "Ctrl+C stops. Press only the key asked for."
for key in "${keys[@]}"; do
    : > "$TMP"
    python3 "$TMP.py" > "$TMP" 2>/dev/null &
    CAP=$!
    sleep 0.5
    read -r -p "Press $key ONCE, then press Enter: " _ </dev/tty
    sleep 0.3
    kill "$CAP" 2>/dev/null; wait "$CAP" 2>/dev/null
    # drop the Enter that ended the step
    got="$(grep -v ' Enter(28) ' "$TMP" | sed -E 's/^[0-9.]+ //' | tr '\n' ';')"
    echo "$key -> ${got:-nothing}" | tee -a "$OUT"
done
echo "Saved to $OUT"
