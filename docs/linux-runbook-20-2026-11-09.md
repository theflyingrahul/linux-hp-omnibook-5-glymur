# Linux runbook for kernel -20, November 9, 2026

From `-20` the daily entry ("Ubuntu on SSD") also has the speakers,
microphones, F9 and the skin-temperature limits. Two test boots cover
everything: the `-19` tests (never run), the EC driver's upstream v2
(Fn lock, the backlight OSD, standby notices), the combo-jack headset,
suspend, the RTC, a UEFI variable write, the NPU, the hardware IDs for
stubble, and then video, external displays and the boot options. The
reboot after B goes to the daily entry for a short check (C). What changed
and why: `docs/kernel-20-plan-2026-11-09.md` and
`docs/ec-review-2026-11-10.md`. `-19` is skipped: `-20` contains it.

Rules for both boots:

- UEFI variables may now be written (owner, 2026-11-09), but only by
  `check-efivars-write.sh`. Still never: `grub-install`, `efibootmgr`,
  fwupd, `mokutil`. The one exception is the read-only `fwupdtool hwids`
  inside `check-chid.sh` (owner, 2026-11-10); the fwupd service stays
  masked and no other fwupd command runs.
- Do not run TPM tools (`tpm2_*`, `systemd-cryptenroll`): Linux has no TPM
  driver on purpose (`docs/tpm-2026-11-06.md`).
- Plug a monitor only at the very end of boot B.
- To go back at any time: "Ubuntu on SSD: previous kernel" boots `-18`.
- If the desktop freezes for seconds and `dmesg` shows `CMD timeout`, stop
  the audio session:
  `systemctl --user stop pipewire pipewire-pulse wireplumber pipewire.socket pipewire-pulse.socket`,
  and note the time.

## Install (on `-18`, now)

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

It checks every file on the stick, installs `-20` (`-18` becomes the
previous kernel), mounts `efivarfs` read-write from the next boot, installs
HP's CDSP FastRPC files, the plain audio topology (with the headset graphs)
and copies the check scripts to your home folder. Reboot into "Ubuntu on
SSD: test device tree".

## A. First boot: test device tree, normal options

Have at hand: a USB mouse or keyboard receiver (no hub), a USB-C stick or
drive, the combo-jack headset (4-pole, with microphone), the charger. Keep music playing on the speakers
from step 5 to step 11.

1. **Input first.** Keyboard, touchpad, touchscreen. If input is dead,
   reboot to "previous kernel" and hand back the boot report.
2. **Boot report:** `/var/log/glymur/boot-*.txt` reads release
   `7.3.0-glymur-20`, model `... (test)`, no `CMD timeout`.
   Also save the hardware IDs that distributions use to pick this
   laptop's device tree (systemd-stub, Ubuntu's stubble, Omarchy), for
   our own stubble pull request: `sudo bash ~/check-chid.sh`, with no
   external monitor plugged in. It saves `systemd-analyze chid`, stubble's
   own `hwids.py` output (the file its `hwids/txt` takes, with the panel's
   EDID IDs), `fwupdtool hwids` (what stubble's README asks for), the
   SMBIOS strings without serials, and the device tree's compatible.
   Read-only. And the random-number generator and crypto engine core
   (`-19`'s config):

        cat /sys/class/misc/hw_random/rng_current
        journalctl -k -b | grep -iE "qce|qcom.rng|trng" | head
3. **UEFI write:** `sudo bash ~/check-efivars-write.sh`. It should print
   `PASS: written and read back`. (Boot B checks that it survived.)
4. **RTC:** `sudo bash ~/check-rtc.sh`. It says whether the RTC holds UTC
   or local time and fires one alarm 20 s ahead (`wakealarm` empty
   afterwards). If it holds local time, answer `y` to `set-local-rtc`.
4b. **EC, as the upstream v2 driver has it:** `sudo bash ~/check-ec.sh`.
   The keyboard backlight level is now the `platform::kbd_backlight`
   LED: after each F5 press it should read 1, 0, 2 as before, writing to
   it changes nothing, and GNOME should show its keyboard-brightness OSD
   (answer each time). New in v2, from `docs/ec-review-2026-11-10.md`:
   the function-key lock. It reads `fn_lock`, asks you to press F7, then
   Left Shift+Fn (it waits for the EC's notification), twice. From the
   corrected v2 it never writes the mode (on `-20` a write flipped the
   row; `docs/runbook-results-20-2026-11-10.md`), and it asks for a 3 s
   hold of F5 and of F6 to catch the timeout change. Also fan,
   temperatures, the backlight timeout and both mute LEDs, as on `-13`.
   The script logs every EC event the driver sees. This gates sending
   v2.
4c. **Function row, optional:** `sudo bash ~/check-hotkeys.sh`, one key at
   a time (F1–F12, Fn+F1–F12, Fn, Copilot, F2's emoji chord), to compare
   with `-18`'s map now that the EC driver is v2.
5. **Speakers and microphones:** `sudo bash ~/check-audio.sh`, then start
   music and, in a second terminal, the long audio watch:
   `sudo bash ~/watch-audio.sh 3600`. Leave both running and use the laptop
   normally for the next steps. This is `-19`'s hour-long session for the
   DSP stall of `-17` (815 s), now on `-20`.
6. **Headset jack, with the combo headset (microphone and buttons):**
   `sudo bash ~/check-headset.sh`. Plug it in when it asks and say what it
   is; keep it away from your ears for the tones. Then: a tone left and
   right, the left tone again at a quarter and at half of the headset
   volume range (is the second louder? `-20`'s SoundWire page cache,
   `backports/0085`, keeps the codec's two-byte volume writes whole), 5 s
   spoken into its microphone, that recording played back in the headset,
   each button pressed once (15 s), and unplugging it.
7. **USB:** the mouse or receiver straight into each USB-C port in turn,
   then into the USB-A port, `sudo bash ~/check-usb.sh` after each. Until
   `-18` these failed with `error -71` on every port; `-20` adds the PHY's
   SE0 timeout and the repeaters' 3 V rail. Then the USB-C stick in each
   USB-C port (SuperSpeed, new PHY settings): `lsusb -t` shows `5000M` or
   `10000M`.
8. **Charging:** `sudo bash ~/charging-watch.sh`; unplug and replug the
   charger once. Then `sudo bash ~/check-battmgr-notify.sh`: it counts the
   battery manager's notifications while you unplug and replug again
   (charger-change events, `backports/0023–0025`).
9. **GPU:** `bash ~/check-mesa.sh`.
10. **NPU:** `sudo bash ~/check-npu.sh` (needs the network for its
    packages).
11. **Power button:** a short press opens GNOME's power-off dialog; cancel.
12. **End of the audio hour:** when `watch-audio.sh` finishes,
    `journalctl -k -b | grep -E "CMD timeout|Parity error|clsh" | head`.
    Stop the music.
13. **Suspend, last:** first plug the USB mouse into one USB-C port and the
    USB-C stick into the other, and have Wi-Fi connected and the charger
    in: `-20`'s suspend fixes are for exactly these (xHCI reset on resume,
    `backports/0079`/`0084`; Wi-Fi over MHI, `0077`/`0078`; a USB-C event
    during sleep, `0076`). Then `sudo bash ~/check-suspend.sh`. Three
    cycles: it suspends and an RTC alarm wakes it (about 40 s; if not,
    press the power button after 90 s); then you close the lid, unplug and
    replug the charger while it sleeps, and open it; then it suspends and
    you press the power button after 20 s. A fourth cycle, which does not
    count towards keeping suspend: the lid closed on AC for 2 minutes (the
    Zenbook A16's lid line wakes it there; Tyler's filter for that is not
    in `-20`). Each cycle logs its wake IRQ and asks what the fan, the
    keyboard backlight and the power LED did while it slept (the EC driver
    now tells the EC about standby, as HP's firmware does on Windows),
    whether the mouse and Wi-Fi came back, and whether the screen,
    keyboard and touchpad came back. If the first three
    worked, run it once more with `--sync-state` (deeper sleep: it
    releases the clocks the GPU management unit holds), then answer `y` to
    keep suspend. If a resume hangs: hold the power button for 10 s and
    boot normally; suspend is masked again automatically.

## B. Second boot: A/V device tree, without Ubuntu's generic options

1. Before rebooting, keep WirePlumber away from the video nodes for this
   boot:

        mkdir -p ~/.config/wireplumber/wireplumber.conf.d
        cp ~/glymur-iris-test/52-no-v4l2-monitor.conf ~/.config/wireplumber/wireplumber.conf.d/

2. Reboot. In GRUB highlight "Ubuntu on SSD: test device tree" and press
   `e`. On the `set glymur_dtb=` line change
   `mahua-hp-omnibook-5-bf1xxx-test.dtb` to
   `mahua-hp-omnibook-5-bf1xxx-test-av.dtb`; on the line starting with
   `linux`, delete the word `$cmdline` (keep everything else). Ctrl-X boots.
   If the screen stays dark, input is dead or it hangs for two minutes:
   hold the power button, do the same edit but keep `$cmdline`, and note
   which.
3. **UEFI write survived:** `sudo bash ~/check-efivars-write.sh --verify`
   (`PASS: survived the reboot unchanged`, then `deleted`).
4. **Boot options:**

        cat /proc/cmdline
        sudo dmesg | grep -iE "address authentication|Disabling unused|genpd.*unused|clk.*unused"
        grep -i paca /proc/cpuinfo | head -1

   Then briefly: keyboard, touchpad, Wi-Fi, a sound on the speakers, the
   camera, the brightness keys.
5. **Suspend without `pd_ignore_unused`** (only if A's suspend worked):
   `sudo bash ~/check-suspend.sh --sync-state`.
6. **Video:** `sudo bash ~/check-video.sh --mahua` (the Mahua trials of
   `-19`; it stops by itself if a trial hangs the decoder).
7. **External display, last:** `sudo bash ~/check-display.sh`, with a
   monitor or USB-C display adapter in one USB-C port, then the other. If
   the machine hangs, hold the power button; that ends the boot.
8. Afterwards:
   `rm ~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf`,
   and reboot into C.

## C. The daily entry, a few minutes (the reboot after B)

Boot "Ubuntu on SSD", the daily device tree. `-20` moved into it what
the test tree proved (the EC event line, the skin-temperature zones, the
speakers and microphones, the USB-C repeaters), and neither A nor B boots it.

1. The boot report reads model `HP OmniBook 5 ...` without `(test)`, and
   its thermal section lists the EC's skin zones.
2. A sound on the speakers and a short recording from the microphones
   (`sudo bash ~/check-audio.sh`, the first steps are enough), F6 and F9
   with their LEDs.
3. The USB-C stick in each USB-C port: `lsusb -t` shows `5000M` or
   `10000M`.
4. If all of that works, this is the entry to use from now on; the test
   entry stays for the PMK8850 and the headset.

## Hand back

- `/var/log/glymur/*.txt` from all three boots: the boot reports,
  `efivar-write-*`, `rtc-test-*`, `ec-test-*`, `hotkeys-*`, `audio-test-*`, `audio-watch-*`,
  `headset-test-*`, `usb-test-*`, `charging-watch-*`, `battmgr-notify-*`, `npu-test-*`,
  `suspend-test-*`, `video-test-*`, `display-test-*`, `chid.txt`,
  `chid-*`, `stubble-hwids-*`, `fwupd-hwids-*`.
- The times of any freeze, what boot B's first try did if it failed, and
  which suspend cycles came back.
- The `-18` laptop session's private logs, still only on the SSD: copy
  `.work/k18-raw-2026-11-05/` from the checkout there to the stick's FAT
  partition (`glymur-logs/`).

Raw journals stay private; the sanitized logs go into `captures/`.
