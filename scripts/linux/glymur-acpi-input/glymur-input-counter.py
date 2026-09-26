#!/usr/bin/env python3
"""Count evdev events per I2C-HID input device without recording contents.

Only event *types* are tallied (EV_KEY, EV_ABS, EV_REL, ...). Key codes,
coordinates, and values are never stored, so typed text cannot be recovered
from the output.
"""

import argparse
import glob
import os
import select
import struct
import time

EVENT = struct.Struct("@llHHi")
TYPE_NAMES = {0x01: "EV_KEY", 0x02: "EV_REL", 0x03: "EV_ABS", 0x04: "EV_MSC", 0x05: "EV_SW"}


def i2c_input_devices(match_all):
    devices = []
    for node in sorted(glob.glob("/sys/class/input/event*")):
        real = os.path.realpath(os.path.join(node, "device"))
        if not match_all and "/i2c-" not in real:
            continue
        try:
            with open(os.path.join(node, "device", "name"), encoding="utf-8") as handle:
                name = handle.read().strip()
        except OSError:
            name = "unknown"
        devices.append(("/dev/input/" + os.path.basename(node), name, real))
    return devices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--all", action="store_true", help="include non-I2C input devices")
    args = parser.parse_args()

    devices = i2c_input_devices(args.all)
    handles = {}
    counts = {}
    for path, name, real in devices:
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as error:
            print(f"open-failed {path} {name!r}: {error}")
            continue
        handles[fd] = path
        counts[path] = {"name": name, "sysfs": real, "types": {}}

    print(f"watching {len(handles)} device(s) for {args.seconds} s")
    deadline = time.monotonic() + args.seconds
    while handles and time.monotonic() < deadline:
        ready, _, _ = select.select(list(handles), [], [], 1.0)
        for fd in ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError as error:
                print(f"read-failed {handles[fd]}: {error}")
                os.close(fd)
                del handles[fd]
                continue
            for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, ev_type, _, _ = EVENT.unpack_from(data, offset)
                if ev_type == 0:  # EV_SYN carries no user content; skip.
                    continue
                label = TYPE_NAMES.get(ev_type, f"type{ev_type}")
                types = counts[handles[fd]]["types"]
                types[label] = types.get(label, 0) + 1
    for fd in handles:
        os.close(fd)

    for path, info in counts.items():
        summary = ", ".join(f"{k}={v}" for k, v in sorted(info["types"].items())) or "no events"
        print(f"{path} {info['name']!r}: {summary}")
        print(f"    {info['sysfs']}")
    if not counts:
        print("no I2C input devices present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
