# Linux runbook for kernel -16, October 21, 2026

For the first boot of kernel `-16` on "Ubuntu on SSD: test device tree"
(`docs/kernel-16-plan-2026-10-21.md` says why). Everything here is read-only
or a normal use of the laptop. Install first, from the USB kit staged with
the `-16` tarball (`install-from-usb.sh` defaults to `-16`; it also copies
`watch-audio.sh` to the home directory):

    bash install-from-usb.sh

Do **not** plug a monitor or a DisplayPort adapter into the USB-C ports on
this kernel: DisplayPort is off, and the failure of `-15` is not fixed.

1. **Boot report.** `/var/log/glymur/boot-*.txt` after 60 s. Look for the
   release `7.3.0-rc4-glymur-16`, the board model `... (test)`, and, in the
   kernel log, none of `Thermal zone name`, `Failed to register thermal
   zone`, `probe with driver hp-omnibook-5-ec failed`.
2. **EC.** `sudo bash check-ec.sh`: the hwmon device, the four
   `ec-therm*-thermal` zones (`cat /sys/class/thermal/thermal_zone*/type`),
   `platform::mute` and `platform::micmute`, the EC interrupt count. Then
   runbook `2026-10-20` steps 4b and 4d (F9 edges and raw keyboard reports,
   they need keypresses) and step 9 (120 s `stress-ng --cpu 12`, now with
   skin zones that can throttle).
3. **Speakers.** In a terminal, from login:
   `sudo bash watch-audio.sh 3600`. Use the laptop normally (a video with
   sound, a call). Afterwards `sudo bash check-audio.sh`. What to note:
   whether `wsa884x` still prints `supply vdd-io not found` (it must not),
   whether the amplifiers stay `ATTACHED`, and, if they drop, the time and
   the dump `watch-audio.sh` wrote at that second.
4. **Video.** `sudo bash check-video.sh`. A pass shows the decoder device
   in `v4l2-ctl --list-devices` and `h264_v4l2m2m` decoding; a failure's
   first power-domain line (`mvs0`, `mvs1` or `mxc`) says whether the
   second core was the whole problem.
5. **Rails.** `grep -H . /sys/class/regulator/regulator.*/name` shows
   `vreg_l15b_e0_1p8` and `vreg_l18b_e0_1p2`; both `state` files read
   `enabled`. USB-A and a USB-C device should still enumerate (their PHYs
   share L15B).
6. **Camera, Bluetooth, touchscreen** as on `-15`: nothing here changes
   them, a quick look is enough to catch a regression from the new rails.

Hand back `/var/log/glymur/*.txt` from this boot; the first thing to read is
the `-16` kernel log for `regulator`, `wsa884x`, `iris`, `gdsc` and
`hp-omnibook-5-ec`.
