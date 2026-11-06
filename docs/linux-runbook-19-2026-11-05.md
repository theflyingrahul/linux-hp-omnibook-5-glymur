# Linux runbook for kernel -19, November 5, 2026

Kernel `7.3.0-glymur-19` on "Ubuntu on SSD: test device tree". What changed
and why: `docs/kernel-19-plan-2026-11-05.md`. Everything here is read-only
or a normal use of the laptop. The USB kit holds the package
`glymur-kernel-7.3.0-glymur-19.tar.gz` (sha256 `67a8bb32…`); the
installer checks every file on the stick before it installs anything.

Order of boots: A on `-18`, then B and C on `-19`, then D (one edited
boot), then E if there is time (another edited boot). Each later part only
needs the one before it to have finished.

- Do **not** plug a monitor or a DisplayPort adapter into the USB-C ports.
- UEFI variables stay read-only (`docs/uefi-variables-2026-10-23.md`).
- Do not run TPM tools (`tpm2_*`, `systemd-cryptenroll`): Linux has no TPM
  driver on purpose (`docs/tpm-2026-11-06.md`).
- To go back: "Ubuntu on SSD: previous kernel" boots `-18`.
- If the desktop freezes for seconds at a time and `dmesg` shows
  `CMD timeout`, stop the audio session:
  `systemctl --user stop pipewire pipewire-pulse wireplumber pipewire.socket pipewire-pulse.socket`.

## A. On `-18`, before installing `-19`: one long audio session

This settles whether dropping `backports/0038–0039` removed the `-17` DSP
stall. It runs on `-18` because `-19` adds the headset path on the same DSP.
Boot "Ubuntu on SSD: test device tree" (still `-18`), start music or a long
video on the speakers, then in a terminal:

    sudo bash ~/watch-audio.sh 3600

Leave it for the full hour while using the laptop normally. Afterwards:

    journalctl -k -b | grep -E "CMD timeout|Parity error|clsh" | head

Note the time of any freeze. No `CMD timeout` after an hour of playback
clears `0038–0039`'s removal as the fix.

## B. Install `-19`

From the USB stick's `glymur-tools/kernels/` directory:

    bash install-from-usb.sh

It defaults to `-19`, builds its initramfs, reinstalls the plain audio
topology (which now has the headset graphs), copies the check scripts
(`check-headset.sh` among them) to your home folder, and keeps part E's
WirePlumber file aside in `~/glymur-iris-test/`. Reboot into "Ubuntu on
SSD: test device tree".

## C. On `-19`

1. **Input first.** Keyboard, touchpad and touchscreen. If input is dead,
   reboot to "previous kernel" and hand back the boot report.
2. **Boot report.** `/var/log/glymur/boot-*.txt`: release
   `7.3.0-glymur-19`, model `... (test)`, no `CMD timeout`.
3. **Speakers and microphones still work:** `sudo bash ~/check-audio.sh`
   (tones left and right, the mute LEDs).
4. **Headset jack:** `sudo bash ~/check-headset.sh`. It asks you to plug in
   a wired headset part-way through, then offers a quiet tone (keep the
   headset away from your ears for the first one) and a 5 s recording from
   the headset microphone. Answer where you heard each tone. Without a UCM
   profile GNOME does not offer the headset yet; that comes after this log.
5. **Charging:** `sudo bash ~/charging-watch.sh`, unplug and replug the
   charger once: `online` follows each plug and GNOME's battery icon follows.
6. **USB devices, now with the repeaters' 3 V rail:** a USB mouse or
   keyboard receiver (full or low speed, plugged straight in, no hub) into
   each USB-C port in turn, then the USB-A port, and `sudo bash ~/check-usb.sh`
   after each. Until `-18` these failed with `device descriptor read/64,
   error -71` on every port (#6). `-19`'s test device tree turns on LDO7_B
   (3.072 V, HP's vote for every USB port) and gives the USB-C repeaters
   their supplies: if the mouse now works on USB-C, that was the cause. The
   USB-A port has no repeater described yet, so a change there would say
   the rail feeds its repeater too.
7. **GPU:** `bash ~/check-mesa.sh`.
8. **Power button:** a short press opens GNOME's power-off dialog; cancel.
9. **RTC, crypto engine, RNG** (new in `-19`, all read-only checks):

        ls /sys/class/rtc/; cat /sys/class/rtc/rtc*/name /sys/class/rtc/rtc*/date /sys/class/rtc/rtc*/time; date -u
        cat /sys/class/misc/hw_random/rng_available /sys/class/misc/hw_random/rng_current
        sudo dmesg | grep -iE "rtc|qce|qcom-rng|sync_state"
        timedatectl

   The RTC should read the same time as the clock after NTP (Linux only
   reads it; it never writes the time). `sync_state() pending due to
   1dfa000.crypto` should be gone now that the crypto engine's core driver
   (`qce-core`) binds; the three lines about `3d6c000.gmu` stay (an
   upstream series, `docs/gmu-sync-state-2026-11-06.md`).

## D. On `-19`, last: one boot without Ubuntu's generic boot options

The USB's GRUB passes `$cmdline` = `clk_ignore_unused pd_ignore_unused
arm64.nopauth` to every SSD entry. All three come from Ubuntu's stock entry
for Snapdragon laptops (its comment: a workaround for an 8cx Gen 3 firmware
bug), not from anything seen on this laptop. They keep every clock and
power domain the firmware left on running for good (power, and it hides
drivers that miss a clock) and switch off pointer authentication, which the
CPU has. This boot tests whether they can go. Nothing on the USB changes:
the edit lasts one boot.

1. Reboot. In the GRUB menu, highlight "Ubuntu on SSD: test device tree"
   and press `e`.
2. On the line that starts with `linux`, delete the word `$cmdline` (keep
   everything else). Press Ctrl-X (or F10) to boot.
3. If the screen stays dark, input is dead or the boot hangs for more than
   two minutes: hold the power button, boot the entry normally, and note
   which. Nothing persists.
4. If the desktop comes up:

        cat /proc/cmdline
        sudo dmesg | grep -iE "address authentication|Disabling unused|genpd.*unused|clk.*unused"
        grep -i paca /proc/cpuinfo | head -1

   Then check briefly: keyboard, touchpad, Wi-Fi, a sound on the speakers,
   the USB-A stick, the camera (`cheese` or the Camera app), the
   brightness keys. Wait for the boot report (60 s), then hand back
   `/var/log/glymur/boot-*.txt` from this boot as well.

If it fails, one more boot later with only `arm64.nopauth` removed
(replace `$cmdline` with `clk_ignore_unused pd_ignore_unused`) separates
pointer authentication from the clock and power-domain clean-up.

## E. Optional, one boot: the Mahua video trials

What Windows does on this chip and why `-17` stalled:
`docs/video-iris-windows-2026-11-06.md`. This boot uses a device tree with
Iris on; nothing on the USB changes.

1. Before rebooting, keep WirePlumber away from the video nodes for this
   boot (an Iris node that cannot power on stalled the audio session on
   `-17`):

        mkdir -p ~/.config/wireplumber/wireplumber.conf.d
        cp ~/glymur-iris-test/52-no-v4l2-monitor.conf ~/.config/wireplumber/wireplumber.conf.d/

2. Reboot. In GRUB, highlight "Ubuntu on SSD: test device tree", press `e`,
   and on the `set glymur_dtb=` line change
   `mahua-hp-omnibook-5-bf1xxx-test.dtb` to
   `mahua-hp-omnibook-5-bf1xxx-test-iris.dtb`. Ctrl-X to boot. The boot
   report's model reads `(test, Iris)`.
3. `sudo bash ~/check-video.sh --mahua`. Four trials, each reloading the
   video driver: the Windows-like set first, then one change at a time.
   Each decodes a 2 s clip with a 30 s limit. If one hangs the decoder, the
   script stops the remaining trials; hand back what it saved.
4. Afterwards remove the WirePlumber file
   (`rm ~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf`)
   and boot the test device tree normally.

## Hand back

- `/var/log/glymur/*.txt` from every boot: `audio-watch-*` from part A;
  the boot report, `audio-test-*`, `headset-test-*`, `usb-test-*` and
  `charging-watch-*` from part C; the boot reports of parts D and E;
  `video-test-*` from part E.
- The times of any freeze, and what part D's boot did if it failed.
- The `-18` laptop session's private logs, which are only on the SSD: copy
  `.work/k18-raw-2026-11-05/` from the repository checkout there to the
  stick's FAT partition (`glymur-logs/`), for example
  `tar czf /media/$USER/*/glymur-logs/k18-raw-2026-11-05.tgz -C <checkout> .work/k18-raw-2026-11-05`.

Raw journals stay private; the sanitized logs go into `captures/`.
