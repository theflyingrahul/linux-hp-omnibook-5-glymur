#!/usr/bin/env python3
"""Observe only right-port mouse motion and buttons during a live USB test."""

import argparse
import errno
import glob
import os
import select
import signal
import struct
import time


EVENT = struct.Struct("@llHHi")
EV_KEY = 0x01
EV_REL = 0x02
REL_AXES = {0: "REL_X", 1: "REL_Y"}
MOUSE_BUTTONS = {0x110: "BTN_LEFT", 0x111: "BTN_RIGHT", 0x112: "BTN_MIDDLE"}
running = True


def stop(_signum, _frame):
    global running
    running = False


def is_target_mouse(sys_path):
    """Exclude keyboards and unrelated input devices before opening evdev."""
    if "/QCOM0F9A:00/" not in os.path.realpath(sys_path):
        return False
    try:
        with open(os.path.join(sys_path, "device", "capabilities", "rel"),
                  encoding="ascii") as handle:
            rel = int(handle.read().split()[-1], 16)
    except (OSError, ValueError, IndexError):
        return False
    return rel & 0x3 == 0x3  # Both REL_X and REL_Y are advertised.


def observe(duration):
    deadline = time.monotonic() + duration
    poller = select.poll()
    devices = {}
    seen = set()
    counts = {"REL_X": 0, "REL_Y": 0, "BTN_LEFT": 0,
              "BTN_RIGHT": 0, "BTN_MIDDLE": 0}
    details = 0

    print(f"observer_start={time.monotonic():.3f} event_size={EVENT.size}", flush=True)
    if EVENT.size != 24:
        print("ERROR: unexpected input_event ABI size; refusing to decode", flush=True)
        return 1

    while running and time.monotonic() < deadline:
        for sys_path in glob.glob("/sys/class/input/event*"):
            name = os.path.basename(sys_path)
            if name in seen or not is_target_mouse(sys_path):
                continue
            seen.add(name)
            try:
                fd = os.open("/dev/input/" + name, os.O_RDONLY | os.O_NONBLOCK)
                poller.register(fd, select.POLLIN | select.POLLERR | select.POLLHUP)
                devices[fd] = [name, b""]
                print(f"mouse_event_device={name} time={time.monotonic():.3f}",
                      flush=True)
            except OSError as exc:
                print(f"open_failed={name} errno={exc.errno}", flush=True)

        for fd, flags in poller.poll(250):
            if fd not in devices:
                continue
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError as exc:
                if exc.errno != errno.ENODEV:
                    print(f"read_failed={devices[fd][0]} errno={exc.errno}",
                          flush=True)
                data = b""
            if not data:
                poller.unregister(fd)
                os.close(fd)
                del devices[fd]
                continue

            name, pending = devices[fd]
            pending += data
            while len(pending) >= EVENT.size:
                _sec, _usec, kind, code, value = EVENT.unpack_from(pending)
                pending = pending[EVENT.size:]
                label = (REL_AXES.get(code) if kind == EV_REL else
                         MOUSE_BUTTONS.get(code) if kind == EV_KEY else None)
                if label is None:
                    continue
                counts[label] += 1
                if details < 200:
                    print(f"event={name} time={time.monotonic():.3f} "
                          f"{label}={value}", flush=True)
                    details += 1
            devices[fd][1] = pending

    for fd in devices:
        poller.unregister(fd)
        os.close(fd)
    print("summary " + " ".join(f"{key}={value}" for key, value in counts.items()),
          flush=True)
    print(f"observer_stop={time.monotonic():.3f}", flush=True)
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=int, default=80)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    raise SystemExit(observe(args.duration))
