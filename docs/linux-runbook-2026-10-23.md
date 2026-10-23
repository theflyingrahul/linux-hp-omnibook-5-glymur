# Linux runbook for kernel -17, October 23, 2026

For the first boot of kernel `7.3.0-rc4-glymur-17` on "Ubuntu on SSD: test
device tree". What `-17` adds is in `patches/README.md` ("Before building
`-17`" onward) and `docs/progress-log.md`. Everything here is read-only or a
normal use of the laptop, apart from acknowledging EC events (step 2),
which is what HP's own tables do.

Do **not** plug a monitor or a DisplayPort adapter into the USB-C ports:
DisplayPort is still off.

## 0. Install (on the running `-16` system)

From the USB stick's `glymur-tools/kernels/` directory, as for `-16`:

    bash install-from-usb.sh
    sudo bash install-audio.sh --speaker-eq

`install-from-usb.sh` defaults to `-17`, mounts `efivarfs` read-only from
the next boot on, installs HP's boot logo for plymouth, and installs the
plain topology;
the second line replaces it with the speaker filter variant
(`docs/audio-speaker-eq-2026-10-23.md`), so one boot tests both the kernel
and the filter. Then reboot into "Ubuntu on SSD: test device tree".

## 1. Boot report

`/var/log/glymur/boot-*.txt` after 60 s: release `7.3.0-rc4-glymur-17`,
model `... (test)`. In the kernel log: no `probe ... failed` for
`hp-omnibook-5-ec`, `qcom_battmgr`, `pmic_glink` or `q6apm`.

## 2. EC events and F9 (issue #11)

The driver now reads the EC's event register `0x00`
(`docs/audit-2026-10-22.md`).

1. `grep -i ec /proc/interrupts` twice, 10 s apart, with the laptop idle.
   On `-16` the EC line fired about 9 times a second; it should now stay
   nearly still.
2. `sudo bash ~/check-hotkeys.sh`: F9 should now arrive as `KEY_MICMUTE`
   from the EC input device and mute the microphone in GNOME (the F9 LED
   follows); F11 as `KEY_PROG2`.
3. Only if F9 still sends nothing: `sudo bash ~/ec-event-capture.sh`, which
   unbinds the EC driver, logs the event byte on each edge, and rebinds it.
   After it, the EC driver loses its interrupt until the next boot (a known
   issue), so run it last.

## 3. Speakers with HP's filter (issue #2)

Play music or a video. Expected: less bass and less boom than on `-16`,
closer to Windows; no distortion. Then `sudo bash ~/check-audio.sh` and
look in its kernel log for errors mentioning `0x6053` (the filter module)
or `APM_CMD_SET_CFG`. If playback fails or sounds wrong:
`sudo bash install-audio.sh` (no option) from the same USB directory and
reboot to go back.

## 4. Charger and battery (issue #15)

`sudo bash ~/charging-watch.sh`, then unplug and replug the charger a few
times. Expected now: `qcom-battmgr-ac` or `-usb` `online` follows each plug
(backport `0032`), and GNOME's battery icon changes without delay. With
the battery full on the charger, the status reads `Full`, not
`Not charging` (`0040`).

## 5. Video (issue #9)

`sudo bash ~/check-video.sh --diag`. It runs seven decode trials, reloading
`qcom_iris` for each. Close any video application first. Hand back the
log: the `diag:` lines (the fuse word) and which trial, if any, decodes.

## 6. USB full and low speed (issue #6)

The USB controllers now get their clock rates, performance level and
bandwidth votes (backport `0042`). Plug a USB mouse or keyboard receiver
**directly** into the USB-A port and into each USB-C port (not through a
hub), then `sudo bash ~/check-usb.sh`. On `-16` these failed with
`error -71`.

## 7. UEFI variables and the clock (issues #17, #18)

`timedatectl` should show an RTC time (there was none on `-16`), and
`mount | grep efivars` should show `ro`. Then `sudo bash ~/dump-efivars.sh`
(read-only) and hand back its directory privately. The power button now
reaches the desktop (`KEY_POWER`); expect GNOME's power-off dialog.

## 8. Boot logo

On this boot plymouth should show HP's logo where the firmware drew it,
without a jump (`docs/boot-logo-2026-10-23.md`). If it shows the fallback
still: `plymouth-set-default-theme` should print `bgrt`.

## 9. Quick regression look

Touchscreen, Bluetooth, camera, Wi-Fi, suspend stays masked.

Hand back `/var/log/glymur/*.txt` from this boot.
