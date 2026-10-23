# Linux runbook for kernel -17, October 23, 2026

For the first boot of kernel `7.3.0-rc4-glymur-17` (package sha256
`2161c744…`) on "Ubuntu on SSD: test device tree". What `-17` adds is in
`patches/README.md` ("Before building `-17`" onward) and
`docs/progress-log.md`. Everything here is read-only or a normal use of the
laptop, apart from acknowledging EC events in the last step, which is what
HP's own tables do.

- Do **not** plug a monitor or a DisplayPort adapter into the USB-C ports:
  DisplayPort is still off.
- UEFI variables are readable from this kernel and mounted read-only. Do not
  remount them read-write (`docs/uefi-variables-2026-10-23.md`).
- To go back: "Ubuntu on SSD: previous kernel" boots `-16`.

## 0. Install (on the running `-16` system)

From the USB stick's `glymur-tools/kernels/` directory, as for `-16`:

    bash install-from-usb.sh
    sudo bash install-audio.sh --speaker-eq

`install-from-usb.sh` defaults to `-17`. It also mounts `efivarfs` read-only
from the next boot on (an `/etc/fstab` line), installs HP's firmware logo for
plymouth, and installs the plain audio topology. The second line replaces
that topology with the speaker filter variant
(`docs/audio-speaker-eq-2026-10-23.md`), so one boot tests both. Then reboot
into "Ubuntu on SSD: test device tree".

## 1. Boot logo and boot report

- During boot, plymouth should show HP's logo where the firmware drew it,
  without a jump (`docs/boot-logo-2026-10-23.md`). If it shows Ubuntu's
  fallback instead: `plymouth-set-default-theme` should print `bgrt`, and
  `ls -l /usr/share/plymouth/themes/spinner/bgrt-fallback.png` should show
  the installed file.
- `/var/log/glymur/boot-*.txt` after 60 s: release `7.3.0-rc4-glymur-17`,
  model `... (test)`. In its kernel log: no `probe ... failed` for
  `hp-omnibook-5-ec`, `qcom_battmgr`, `pmic_glink`, `q6apm`, `qseecom` or
  `rtc-pm8xxx`.

## 2. Clock and UEFI variables (issues #17, #18)

- `timedatectl` should show an RTC time (there was none on `-16`), close to
  the real time before NTP corrects it.
- `mount | grep efivars` should show `ro`.
- `sudo bash ~/dump-efivars.sh` (read-only): it lists every variable and
  names `RTCInfo` and `SmartAmpCalibrationData` if they are visible. Hand
  back its directory **privately**: it holds machine-specific data.
- The power button now reaches the desktop (`KEY_POWER`). A short press
  should open GNOME's power-off dialog; cancel it. Save your work first.

## 3. EC interrupt and F9 (issue #11)

The driver now reads the EC's event register `0x00`
(`docs/audit-2026-10-22.md`).

1. `grep -i ec /proc/interrupts` twice, 10 s apart, with the laptop idle.
   On `-16` the EC line fired about 9 times a second; it should now stay
   nearly still.
2. `sudo bash ~/check-hotkeys.sh`: F9 should arrive as `KEY_MICMUTE` from
   the EC input device and mute the microphone in GNOME (the F9 LED
   follows); F11 as `KEY_PROG2`; F5 changes the keyboard backlight in the
   EC as before.

If F9 still sends nothing, leave the event capture for step 9.

## 4. Speakers with HP's filter (issue #2)

Play music or a video. Expected: less bass and less boom than on `-16`,
closer to Windows; no distortion. Then `sudo bash ~/check-audio.sh` and look
in its kernel log for errors mentioning `0x6053` (the filter module) or
`APM_CMD_SET_CFG`. If playback fails or sounds wrong: `sudo bash
install-audio.sh` (no option) from the USB directory and reboot to go back.

## 5. Charger and battery (issue #15)

`sudo bash ~/charging-watch.sh`, then unplug and replug the charger a few
times. Expected: `qcom-battmgr-ac` or `-usb` `online` follows each plug
(backport `0032`), and GNOME's battery icon changes without delay. With the
battery full on the charger, the status reads `Full`, not `Not charging`
(`0040`).

## 6. USB full and low speed (issue #6)

The USB controllers now get their clock rates, performance level and
bandwidth votes (backport `0042`). Plug a USB mouse or keyboard receiver
**directly** into the USB-A port and into each USB-C port (not through a
hub), then `sudo bash ~/check-usb.sh`. On `-16` these failed with
`error -71`.

## 7. Video (issue #9)

Close any video application, then `sudo bash ~/check-video.sh --diag`. It
runs seven decode trials, reloading `qcom_iris` for each
(`docs/video-iris-fuse-2026-10-23.md`). Hand back the log: the `diag:` lines
(the fuse word) and which trial, if any, decodes.

## 8. Quick regression look

Touchscreen, Bluetooth, camera and Wi-Fi as on `-16`. Suspend stays masked.

## 9. Last, and only if F9 sent nothing in step 3

`sudo bash ~/ec-event-capture.sh` unbinds the EC driver, logs the event
byte on each edge for the keys it asks for, and rebinds it. Afterwards the
EC driver has no interrupt until the next boot (a known issue), which is
why it comes last.

## Hand back

`/var/log/glymur/*.txt` from this boot (boot report, hotkeys, audio,
charging, USB, video, EC events), and the `efivars-*` directory privately.
