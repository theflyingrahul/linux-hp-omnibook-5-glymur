# Linux runbook for kernel -20, November 9, 2026

From `-20` the daily entry ("Ubuntu on SSD") also has the speakers,
microphones, F9 and the skin-temperature limits; both test boots below
still use the test entries. Two boots cover everything: the `-19` tests (never run), suspend, the RTC,
a UEFI variable write, the NPU, and then video, external displays and the
boot options. What changed and why: `docs/kernel-20-plan-2026-11-09.md`.
`-19` is skipped: `-20` contains it.

Rules for both boots:

- UEFI variables may now be written (owner, 2026-11-09), but only by
  `check-efivars-write.sh`. Still never: `grub-install`, `efibootmgr`,
  fwupd, `mokutil`.
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
drive, a wired headset, the charger. Keep music playing on the speakers
from step 5 to step 11.

1. **Input first.** Keyboard, touchpad, touchscreen. If input is dead,
   reboot to "previous kernel" and hand back the boot report.
2. **Boot report:** `/var/log/glymur/boot-*.txt` reads release
   `7.3.0-glymur-20`, model `... (test)`, no `CMD timeout`.
   Also save the hardware IDs that distributions use to pick this
   laptop's device tree (systemd-stub, Ubuntu's stubble, Omarchy):
   `systemd-analyze chid | tee /var/log/glymur/chid.txt` (needs systemd
   257 or later; it only reads the firmware's SMBIOS strings).
3. **UEFI write:** `sudo bash ~/check-efivars-write.sh`. It should print
   `PASS: written and read back`. (Boot B checks that it survived.)
4. **RTC:** `sudo bash ~/check-rtc.sh`. It says whether the RTC holds UTC
   or local time and fires one alarm 20 s ahead (`wakealarm` empty
   afterwards). If it holds local time, answer `y` to `set-local-rtc`.
4b. **EC, as the upstream v2 driver has it:** `sudo bash ~/check-ec.sh`.
   The keyboard backlight level is now the `platform::kbd_backlight`
   LED: after each F5 press it should read 1, 0, 2 as before, and
   writing to it changes nothing. Also fan, temperatures, the backlight
   timeout and both mute LEDs, as on `-13`. This is what the reply to
   the v1 review promises, so it gates sending v2.
5. **Speakers and microphones:** `sudo bash ~/check-audio.sh`, then start
   music and, in a second terminal, the long audio watch:
   `sudo bash ~/watch-audio.sh 3600`. Leave both running and use the laptop
   normally for the next steps. This is `-19`'s hour-long session for the
   DSP stall of `-17` (815 s), now on `-20`.
6. **Headset jack:** `sudo bash ~/check-headset.sh` (plug the headset when
   it asks; keep it away from your ears for the first tone).
7. **USB:** the mouse or receiver straight into each USB-C port in turn,
   then into the USB-A port, `sudo bash ~/check-usb.sh` after each. Until
   `-18` these failed with `error -71` on every port; `-20` adds the PHY's
   SE0 timeout and the repeaters' 3 V rail. Then the USB-C stick in each
   USB-C port (SuperSpeed, new PHY settings): `lsusb -t` shows `5000M` or
   `10000M`.
8. **Charging:** `sudo bash ~/charging-watch.sh`; unplug and replug the
   charger once.
9. **GPU:** `bash ~/check-mesa.sh`.
10. **NPU:** `sudo bash ~/check-npu.sh` (needs the network for its
    packages).
11. **Power button:** a short press opens GNOME's power-off dialog; cancel.
12. **End of the audio hour:** when `watch-audio.sh` finishes,
    `journalctl -k -b | grep -E "CMD timeout|Parity error|clsh" | head`.
    Stop the music.
13. **Suspend, last:** `sudo bash ~/check-suspend.sh`. Three cycles: it
    suspends and an RTC alarm wakes it (about 40 s; if not, press the power
    button after 90 s); then you close the lid for 20 s and open it; then it
    suspends and you press the power button after 20 s. After each cycle it
    asks whether the screen, keyboard and touchpad came back. If all three
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
   and boot "Ubuntu on SSD: test device tree" normally.

## Hand back

- `/var/log/glymur/*.txt` from both boots: the two boot reports,
  `efivar-write-*`, `rtc-test-*`, `ec-test-*`, `audio-test-*`, `audio-watch-*`,
  `headset-test-*`, `usb-test-*`, `charging-watch-*`, `npu-test-*`,
  `suspend-test-*`, `video-test-*`, `display-test-*`, `chid.txt`.
- The times of any freeze, what boot B's first try did if it failed, and
  which suspend cycles came back.
- The `-18` laptop session's private logs, still only on the SSD: copy
  `.work/k18-raw-2026-11-05/` from the checkout there to the stick's FAT
  partition (`glymur-logs/`).

Raw journals stay private; the sanitized logs go into `captures/`.
