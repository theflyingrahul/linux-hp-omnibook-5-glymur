#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Prints the keyboard backlight timeout each time the EC driver's sysfs
# attribute is notified with a new value. Reads only on notifications.

import glob
import select
import sys
import time

PATTERN = "/sys/bus/i2c/drivers/hp-omnibook-5-ec/*/kbd_backlight_timeout"


def find():
    while True:
        found = glob.glob(PATTERN)
        if found:
            return found[0]
        time.sleep(10)


def main():
    f = open(find())
    poll = select.poll()
    poll.register(f, select.POLLPRI | select.POLLERR)
    last = None
    while True:
        try:
            f.seek(0)
            value = f.read().strip()
        except OSError:
            value = last
            time.sleep(1)
        if last is not None and value != last:
            print(value, flush=True)
        last = value
        poll.poll()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
