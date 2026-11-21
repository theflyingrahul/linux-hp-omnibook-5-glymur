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

## Remaining steps, November 21

Done on the first `-23` boot: A1 to A4, A6, A8, and half of A5
(`docs/runbook-results-23-2026-11-21.md`). The fixed `check-headset.sh`
and `check-usb.sh` are in your home directory. Order: A5, A7, then
optionally B, then C. The boot stick is always in the USB-A port from
power-on (it is the boot loader), so no note is needed for that.

### A5, rest: USB-C stick and runtime resume (test tree, now)

1. The USB-C stick in connector 0 (hinge side). The charger can stay in
   connector 1. Wait 5 s, then:

        lsusb -t
        sudo bash ~/check-usb.sh

   In `lsusb -t`, the stick's `Mass Storage` line should end in `5000M` or
   `10000M`. Bus numbers change with each port's role, so go by the line,
   not the bus number.
2. Swap them, the stick in connector 1 and the charger in connector 0, and
   repeat.
3. Runtime resume (`0087`), on battery: the stick in one USB-C port, the
   Dell receiver in the other. Then:

        for c in /sys/bus/usb/devices/*/power/control; do echo auto | sudo tee "$c" >/dev/null; done
        sleep 15
        for c in /sys/bus/usb/devices/*/power/control; do echo on | sudo tee "$c" >/dev/null; done
        journalctl -k --since "-1 min" | grep -E "port_wait_reset|reset .*USB|-16"
        lsblk -o NAME,SIZE,TRAN | grep usb

   The `journalctl` line should print nothing. The last line should list
   both sticks (the boot stick on USB-A and the USB-C stick). Move the mouse
   too: it should work.

### A7: suspend, from a text console (test tree)

Allow 30 minutes; the 10-minute drain cycle is part of it. Have the phone
ready for photographs.

1. **Set up:**
    - the charger in one USB-C port, the Dell receiver in the other. There
      are only two USB-C ports, so the USB-C stick sits this one out;
    - Wi-Fi connected.
2. Press **Ctrl+Alt+F3** and log in with your user name and password.
   Ctrl+Alt+F2 goes back to the desktop later.
3. Run:

        sudo bash ~/check-suspend.sh --console

   It runs two `pm_test` passes first (freezer, devices), with no sleep and
   nothing to do. Then come four cycles. Each one prints what to do, then
   sleeps:

    | Cycle | What you do |
    | --- | --- |
    | `rtc` | The RTC has no time, so the alarm will not fire. After about 20 s, press a key or the touchpad. If it is still asleep after a few seconds, press the power button briefly. |
    | `lid` | Close the lid. While it sleeps, unplug the charger, wait 10 s, plug it back in, wait 10 s more, then open the lid. |
    | `button` | It suspends after 3 s. Wait 20 s, then press the power button briefly. |
    | `lid-ac` | Charger in: close the lid, leave it closed for 2 minutes, then open it. |

   While each cycle sleeps, watch the fan, the keyboard backlight and the
   power LED. After each cycle, seven questions follow:
    - fan, keyboard backlight and power LED while it slept;
    - whether the screen came back;
    - whether the keyboard and touchpad work;
    - whether the USB mouse moves the pointer: answer `y`, `n`, or `none
      plugged in`. On the console there is no pointer, so answer whether
      the mouse's light is on, or `unsure`;
    - Wi-Fi: answer `unsure` (no browser on the console). The script records
      the network state itself.
4. **Drain cycle:** to `Measure the sleep drain: 10 minutes on battery with
   the lid closed?`, answer `y`. Then unplug the charger, close the lid,
   wait 10 minutes, open the lid, and plug the charger back in.
5. To `Keep suspend enabled (lid close suspends from now on)?`, answer `n`.
   Suspend is masked again; we lift that only when the cycles are reliable.
6. **If it freezes** at any point (the screen does not come back within
   about a minute, or nothing responds):
    1. Photograph the console's last lines.
    2. Hold the power button for about 10 s, until it is off.
    3. Boot "Ubuntu on SSD: test device tree" again. A one-shot unit masks
       suspend again at this boot.
    4. In a terminal, run:

           journalctl -b -1 -k | tail -200 > ~/suspend-freeze-k23.txt

7. **If every cycle came back,** run it once more with the charger in, this
   time releasing the boot clocks first:

        sudo bash ~/check-suspend.sh --console --sync-state

   Answer `y` to the drain cycle only if you have 10 more minutes.

Look at the `residency cxsd / aosd / ddr` lines and the `mW average` line
after each cycle; they are in the log as well.

### B: the A/V device tree (optional, after A7)

1. The WirePlumber file is already in place
   (`~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf`);
   leave it.
2. Reboot. In GRUB, highlight "Ubuntu on SSD: test device tree" and press
   `e`:
    - on the `set glymur_dtb=` line, change
      `mahua-hp-omnibook-5-bf1xxx-test.dtb` to
      `mahua-hp-omnibook-5-bf1xxx-test-av.dtb`;
    - on the line that starts with `linux`, delete the word `$cmdline`
      and keep everything else.

   Ctrl+X boots. If the screen stays dark, input is dead or it hangs for 2
   minutes: hold the power button, then do the same edit but keep
   `$cmdline`, and note which way it booted.
3. **Boot options:**

        cat /proc/cmdline
        sudo dmesg | grep -iE "address authentication|Disabling unused|genpd.*unused|clk.*unused"
        grep -i paca /proc/cpuinfo | head -1

   Then a quick check: keyboard, touchpad, Wi-Fi, a sound on the speakers,
   the camera, the brightness keys.
4. **Suspend:** only if A7 came back, run
   `sudo bash ~/check-suspend.sh --console --sync-state` from Ctrl+Alt+F3,
   as in A7.
5. **Video:** `sudo bash ~/check-video.sh --mahua`, only if there is time.
   It stops by itself if a trial hangs the decoder.
6. **External display, last:** run `sudo bash ~/check-display.sh` with a
   monitor or USB-C display adapter in one USB-C port, then in the other.
   If it hangs, hold the power button; that ends this boot.

### C: the daily entry (Linux's USB-A values)

1. Reboot into "Ubuntu on SSD", the entry without "test".
2. Wait a minute for the boot report, then:

        f=$(ls -t /var/log/glymur/boot-*.txt | head -1); head -3 "$f"; grep -A8 "USB-A (a000000.usb) link" "$f"

   The model has no `(test)`, and the section reads `HP PHYC overrides in
   the device tree: none`, with the stick at 5000 Mb/s.
3. **Speakers and microphones:** `sudo bash ~/check-audio.sh`; the first
   steps are enough. Then press F6 (speaker mute) and F9 (microphone mute)
   and watch their LEDs.
4. **USB-C stick:** plug it into each USB-C port in turn (the charger in
   the other). Its line in `lsusb -t` should end in `5000M` or `10000M`.
5. **USB-A stress, for the comparison with A4:** if the boot stick is not at
   SuperSpeed (`lsusb -t` shows `5000M` on bus 3), unplug it and plug it
   back in first. Then:

        sudo bash ~/check-usb.sh --ss-stress

   Answer `y` to unmount it. The summary line is what counts.

### Hand back

Say which steps you ran. `/var/log/glymur/` is read from here, so there is
nothing to copy. Also send:
- any photographs;
- `~/suspend-freeze-k23.txt`, if A7 froze;
- for B, whether it booted with or without `$cmdline`.
