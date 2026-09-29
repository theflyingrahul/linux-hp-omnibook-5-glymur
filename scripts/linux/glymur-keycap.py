#!/usr/bin/env python3
# Raw evdev capture for hotkey/LED diagnosis, decoding struct input_event
# from the keyboard, gpio-keys, and the touchpad's Consumer Control HID
# collection at once, since special keys can surface on any of them.
#
#   sudo python3 glymur-keycap.py [seconds]     (default 30s)
#
# Decode codes against /usr/include/linux/input-event-codes.h. The event
# node numbers below match this machine's enumeration order as of
# 2026-09-29 (docs/keyboard-hotkeys-2026-09-29.md); check
# /proc/bus/input/devices and adjust if they differ on a future boot.
import struct, select, sys, time, os

devs = {
    "/dev/input/event0": "gpio-keys",
    "/dev/input/event6": "consumer-control(touchpad-hid)",
    "/dev/input/event7": "keyboard",
}
fds = {}
for path, name in devs.items():
    try:
        fds[os.open(path, os.O_RDONLY)] = (path, name)
    except OSError as e:
        print(f"open failed {path}: {e}", file=sys.stderr)

EVFMT = "llHHi"
EVSIZE = struct.calcsize(EVFMT)

EV_NAMES = {0: "SYN", 1: "KEY", 2: "REL", 3: "ABS", 4: "MSC", 5: "SW", 17: "LED"}

end = time.time() + float(sys.argv[1]) if len(sys.argv) > 1 else time.time() + 30
print(f"capturing for {end - time.time():.0f}s on {list(devs.values())}", flush=True)
while time.time() < end:
    r, _, _ = select.select(list(fds.keys()), [], [], 1.0)
    for fd in r:
        path, name = fds[fd]
        data = os.read(fd, EVSIZE * 8)
        for i in range(0, len(data) - EVSIZE + 1, EVSIZE):
            sec, usec, typ, code, val = struct.unpack(EVFMT, data[i:i+EVSIZE])
            if typ == 0:
                continue
            tname = EV_NAMES.get(typ, str(typ))
            print(f"[{time.strftime('%H:%M:%S')}.{usec//1000:03d}] {name}: type={tname}({typ}) code={code} value={val}", flush=True)
print("done", flush=True)
