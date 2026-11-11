# Linux runbook for kernel -23, November 11, 2026

`-23` replaces `-22`, which was never booted. It is `-22` plus one change
for the USB-A port's SuperSpeed failures (`docs/usb-a-superspeed-2026-11-11.md`):

| Change | For | Tested by |
| --- | --- | --- |
| `glymur-bringup/0006` and HP's two USB3 PHY values (ACPI `\_SB.USB2.PHYC`) in the **test** device tree only | the boot stick dropping out of SuperSpeed (2 of 13 boots) | A1, A4, C |
| from `-22`: `backports/0087` USB2 resume terminations on the eUSB2 PHY | USB after suspend and runtime resume; maybe #6 | A5, A7 |
| from `-22`: `backports/0088` PCIe pipe clocks keep memory and logic on | NVMe (PCIe 5) and Wi-Fi (PCIe 4) | A1, A7 |
| from `-22`: no `CONFIG_NVME_SPEED_SWITCH` | the NVMe link retraining every few seconds | A1, A7 |

The `-20` runbook's rules still hold. "Ubuntu on SSD: previous kernel" now
boots `-21`.

## Install (on `-21`, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

It installs `-23` and the refreshed scripts:
- `check-usb.sh --ss-stress`
- the boot report's USB-A section
- `check-headset.sh` with the full path
- `check-suspend.sh` with `pm_test` and `--console`
- `check-efivars-write.sh --delete`

It also adds the NVMe udev rule, and the backlight timeout OSD extension if
it is not there yet. Before rebooting, eject "UBUNTU 26_0" in Files, so its
FAT is clean. Then reboot into "Ubuntu on SSD: test device tree".

## A. Test device tree (HP's USB-A values)

1. **Boot report:** it reads `7.3.0-glymur-23`, model `(test)`. Its new "USB-A (a000000.usb) link" section shows the
   overrides `00000158 000000a0 00000178 00000090`, two `USB3 lane A …
   (read back …)` lines with the same values, the stick at 5000 Mb/s (or
   10000), and `errors: 0`. Then:

        journalctl -k -b | grep -c "failed to set target rate"
        ls /sys/class/nvme/nvme0/speed 2>&1
        journalctl -k -b | grep -E "UBSAN|Unbalanced|completion timeout"

   The first prints 0, the second says there is no such directory, and the
   third prints nothing.
2. **UEFI:** `sudo bash ~/check-efivars-write.sh --delete` removes the test
   variable that boot B of `-21` left (it prints `deleted`).
3. **Headset:** `sudo bash ~/check-headset.sh` with the combo headset. It
   plays tones through the RX macro, then runs the 12-input microphone scan
   while you talk.
4. **USB-A stress:** `sudo bash ~/check-usb.sh --ss-stress` with the boot
   stick in the USB-A port. Answer `y` to unmount it; it is only read. It
   takes about 3 minutes. The summary line is what counts:
   `back at SuperSpeed N, at high speed N, gone N of 20; link errors in all: N`.
   If the stick is gone at the end, unplug it and plug it back in. If you
   have another USB 3 stick or drive, run it once more with that one in the
   port.
5. **USB-C:** test the mouse in each USB-C port, then the USB-C stick in
   each, and run `sudo bash ~/check-usb.sh` after each. Then test the
   runtime-resume reset that `0087` fixes, with the USB-C stick plugged in
   (it autosuspends; the mouse may not):

        for c in /sys/bus/usb/devices/*/power/control; do echo auto | sudo tee "$c" >/dev/null; done
        sleep 15
        for c in /sys/bus/usb/devices/*/power/control; do echo on | sudo tee "$c" >/dev/null; done
        journalctl -k --since "-1 min" | grep -E "port_wait_reset|reset .*USB|-16"

   Nothing should print, and `lsblk` should still list the stick.
6. **Charging:** run `sudo bash ~/charging-watch.sh`, then
   `sudo bash ~/check-battmgr-notify.sh`.
7. **Suspend, from a text console:** press Ctrl+Alt+F3 and log in. Put the
   mouse in a USB-C port and the stick in the other, with Wi-Fi on. Then:
    1. Run `sudo bash ~/check-suspend.sh --console` and do the cycles.
    2. At the end, answer `y` to the 10-minute drain cycle, **on battery**.
    3. If it freezes: photograph the console's last lines, hold the power
       button, boot normally, and hand back
       `journalctl -b -1 -k | tail -200`.
    4. If it comes back: run it once more with `--sync-state`, charger in.

   Look at the residency lines (`cxsd`, `aosd`, `ddr`) and the mW figure.
   The Wi-Fi's `Timeout waiting for L2 entry` on each suspend is known
   (`docs/usb-a-superspeed-2026-11-11.md`).
8. Not yet run anywhere: the timeout OSD on `-23` (hold F5; it should still
   work), and boot C below.

## B. A/V device tree (only what is new)

The same as in the `-20` runbook: the WirePlumber file first, then the GRUB
edit to `-test-av.dtb` without `$cmdline`. This tree includes the test tree,
so it has HP's USB-A values too. Run B6 (`check-video.sh --mahua`) again
only if nothing else is pending; leave B7 (external displays) for last.

## C. The daily entry (Linux's USB-A values)

"Ubuntu on SSD": the model has no `(test)`. Check:
- the speakers and microphones;
- F6 and F9;
- the USB-C stick at SuperSpeed.

Then run `sudo bash ~/check-usb.sh --ss-stress` with the same stick, for
the comparison with A4. The boot report's USB-A section shows `overrides …
none` here.

From now on, every boot's report counts the USB-A link errors. Note on each
boot whether the stick was in the port from power-on.

## Hand back

- `/var/log/glymur/*.txt` from each boot (boot reports, `usb-test-*`);
- any console photographs;
- which suspend cycles came back.
