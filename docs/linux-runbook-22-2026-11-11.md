# Linux runbook for kernel -22, November 11, 2026

`-22` is `-21` plus what the upstream check of November 11 found useful for
suspend (`patches/README.md`, "Kernel `-22`"):

| Change | For | Tested by |
| --- | --- | --- |
| `backports/0087` USB2 resume terminations on Glymur's eUSB2 PHY (`snps,resume-hs-terminations`, accepted in linux-next) | USB devices after suspend and runtime resume; maybe the full/low-speed `-71` (#6) | 4, 6 |
| `backports/0088` PCIe pipe clocks keep their memory and peripheral logic on (accepted in linux-next) | the NVMe (PCIe 5) and Wi-Fi (PCIe 4) data path | 1, 6 |
| No `CONFIG_NVME_SPEED_SWITCH` | the NVMe link retraining every few seconds, which has no suspend hook | 1, 6 |

The rules of the `-20` runbook still hold. "Ubuntu on SSD: previous kernel"
now boots `-21`.

## Install (on `-21`, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

It installs `-22` and the refreshed scripts (`check-headset.sh` with the full
path, `check-suspend.sh` with `pm_test` and `--console`,
`check-efivars-write.sh --delete`), the NVMe udev rule, and the backlight
timeout OSD extension if it is not there yet. Reboot into "Ubuntu on SSD:
test device tree".

## A. Test device tree

1. **Boot report** reads `7.3.0-glymur-22`, model `(test)`. Then:

        journalctl -k -b | grep -c "failed to set target rate"
        ls /sys/class/nvme/nvme0/speed 2>&1

   The first prints 0 and the second says there is no such directory (the
   feature is not built). Also nothing from
   `journalctl -k -b | grep -E "UBSAN|Unbalanced|completion timeout"`.
2. **UEFI:** `sudo bash ~/check-efivars-write.sh --delete` removes the test
   variable boot B of `-21` left (prints `deleted`).
3. **Headset:** `sudo bash ~/check-headset.sh` with the combo headset: tones
   through the RX macro, then the 12-input microphone scan while you talk.
4. **USB-C:** the mouse in each USB-C port, then the USB-C stick in each,
   `sudo bash ~/check-usb.sh` after each. Then the runtime-resume reset
   that `0087` fixes, with the USB-C stick plugged in (it autosuspends;
   the mouse may not):

        for c in /sys/bus/usb/devices/*/power/control; do echo auto | sudo tee "$c" >/dev/null; done
        sleep 15
        for c in /sys/bus/usb/devices/*/power/control; do echo on | sudo tee "$c" >/dev/null; done
        journalctl -k --since "-1 min" | grep -E "port_wait_reset|reset .*USB|-16"

   Nothing should print, and `lsblk` still lists the stick.
5. **Charging:** `sudo bash ~/charging-watch.sh`, then
   `sudo bash ~/check-battmgr-notify.sh`.
6. **Suspend, from a text console** (Ctrl+Alt+F3, log in), mouse in a
   USB-C port, stick in the other, Wi-Fi on:
   `sudo bash ~/check-suspend.sh --console`. Do the cycles; at the end
   answer `y` to the 10-minute drain cycle **on battery**. If it freezes,
   photograph the console's last lines, hold the power button, boot
   normally and hand back `journalctl -b -1 -k | tail -200`. If it comes
   back, run it once more with `--sync-state` (charger in). The residency
   lines (`cxsd`, `aosd`, `ddr`) and the mW figure are what to look at.
7. Not yet run anywhere: the timeout OSD with `-22` (hold F5; it should
   still work), and boot C below.

## B. A/V device tree (only what is new)

As in the `-20` runbook (WirePlumber file first, then the GRUB edit to
`-test-av.dtb` without `$cmdline`). B6 `check-video.sh --mahua` again only
if nothing else is pending; B7 external displays last.

## C. The daily entry

"Ubuntu on SSD": model without `(test)`, speakers and microphones, F6/F9,
the USB-C stick at SuperSpeed.

## Hand back

`/var/log/glymur/*.txt` from each boot, any console photographs, and which
suspend cycles came back.
