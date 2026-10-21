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
F = 'llHHi'; Z = struct.calcsize(F)
while True:
    r, _, _ = select.select(list(fds), [], [], 1)
    for fd in r:
        b = os.read(fd, Z * 16)
        for i in range(0, len(b) - Z + 1, Z):
            s, u, t, c, v = struct.unpack(F, b[i:i + Z])
            if t == 1 and v != 2:
                print('%.3f %s code=%d %s' % (time.time(), fds[fd], c, 'down' if v else 'up'), flush=True)
PY

{
    echo "kernel: $(uname -r)"
    echo "Each step: the key codes the kernel saw. 113 = mute, 248 = micmute,"
    echo "29+187 = Ctrl+F17, 125+42+193 = Meta+Shift+F23, 164 = play/pause."
} | tee "$OUT"

for key in "F9 (microphone mute)" "F9 (microphone mute)" "F11" "F11" "F6 (speaker mute)" "F5 (keyboard backlight)" "Fn alone" "Copilot key"; do
    : > "$TMP"
    python3 "$TMP.py" > "$TMP" 2>/dev/null &
    CAP=$!
    sleep 0.5
    read -r -p "Press $key ONCE, then press Enter: " _ </dev/tty
    sleep 0.3
    kill "$CAP" 2>/dev/null; wait "$CAP" 2>/dev/null
    # drop the Enter that ended the step
    got="$(grep -v 'code=28 ' "$TMP" | sed -E 's/^[0-9.]+ //' | tr '\n' ';')"
    echo "$key -> ${got:-nothing}" | tee -a "$OUT"
done
echo "Saved to $OUT"
