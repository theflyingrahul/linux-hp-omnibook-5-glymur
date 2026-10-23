# Linux runbook for kernel -18, October 23, 2026

For the first boot of kernel `7.3.0-rc6-glymur-18` on "Ubuntu on SSD: test
device tree". Why `-18` and what changed: `docs/kernel-18-plan-2026-10-23.md`.
Everything here is read-only or a normal use of the laptop.

- Do **not** plug a monitor or a DisplayPort adapter into the USB-C ports.
- UEFI variables stay read-only (`docs/uefi-variables-2026-10-23.md`).
- To go back: "Ubuntu on SSD: previous kernel" boots `-17` with its initramfs.
- If the desktop freezes for seconds at a time and `dmesg` shows
  `CMD timeout`, stop the audio session to release it:
  `systemctl --user stop pipewire pipewire-pulse wireplumber` and the two
  sockets (`pipewire.socket`, `pipewire-pulse.socket`).

## 0. Before installing (on the running `-17` system)

1. **The side project stays off the boot path** (the owner, 2026-10-23):
   disable its boot-time service (`plymouth-job-monitor`) and set plymouth's
   theme back to `bgrt` so the next initramfs carries it:

       sudo systemctl disable --now plymouth-job-monitor.service
       sudo plymouth-set-default-theme bgrt

2. **Remove the `-17` WirePlumber workaround**: Iris is off in `-18`, so the
   v4l2 monitor has nothing to block on.

       rm ~/.config/wireplumber/wireplumber.conf.d/52-no-v4l2-monitor.conf

3. From the USB stick's `glymur-tools/kernels/` directory:

       bash install-from-usb.sh

   It defaults to `-18`, builds its initramfs (an initramfs is in use), and
   reinstalls the plain audio topology and the boot logo. Do not install the
   speaker filter topology yet: the DSP stall comes first.

Reboot into "Ubuntu on SSD: test device tree".

## 1. Input first

The new base changes how the GENI I2C controllers pick their clock
(`backports/0046`). Before anything else: keyboard, touchpad and
touchscreen work, and `dmesg | grep -i "geni\|i2c.*clk\|SE source clock"`
shows no `Unsupported SE source clock` or `Failed to find SE source clock`.
If input is dead, reboot to "previous kernel" and hand back the boot report.

## 2. Boot logo and boot report

- Plymouth shows HP's logo where the firmware drew it
  (`docs/boot-logo-2026-10-23.md`).
- `/var/log/glymur/boot-*.txt`: release `7.3.0-rc6-glymur-18`, model
  `... (test)`. The boot-time `CMD timeout for [1001021]` should be gone (the
  GPR race fix in the new base). No `qcom-iris` and no `rtc-pm8xxx` lines:
  both are off.

## 3. Audio, the bisect (issue #2 and the `-17` stall)

`backports/0038–0039` are out. Use audio normally for a while (music, a
video): sound from the speakers, the volume keys, F6. Then, with music
playing, restart the session three times, one minute apart, the trigger on
`-17`:

    systemctl --user restart wireplumber

After each, `dmesg | grep -E "CMD timeout|Parity error"`. A stall shows as
`CMD timeout for [1001004]` within seconds; if it comes, stop the audio
session as above and note the time. Then `sudo bash ~/check-audio.sh`.

## 4. The `-17` steps not run yet

1. `grep -i ec /proc/interrupts` twice, 10 s apart: still nearly still.
2. `sudo bash ~/check-hotkeys.sh`: F9 as `KEY_MICMUTE` from the EC input
   device, muting the microphone in GNOME with its LED; F11 as `KEY_PROG2`.
3. `sudo bash ~/charging-watch.sh`, unplug and replug the charger:
   `online` follows each plug, GNOME's battery icon follows without delay.
4. A USB mouse or keyboard receiver directly into the USB-A port and each
   USB-C port, then `sudo bash ~/check-usb.sh`.
5. `bash ~/check-mesa.sh` and a short `glmark2` run: the GPU under load.
6. The power button: a short press opens GNOME's power-off dialog; cancel.

## 5. Last, and only if F9 sent nothing

`sudo bash ~/ec-event-capture.sh` (it leaves the EC driver without its
interrupt until the next boot).

## Hand back

`/var/log/glymur/*.txt` from this boot, `dmesg`, and the times of any
freeze. Raw journals stay private.
