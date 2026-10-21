# Runbook results, kernel `-16`, 2026-10-21

First boot of `7.3.0-rc4-glymur-16` on the test device tree, after the Ubuntu
26.10 upgrade (see the end of this note). Raw logs: `captures/2026-10-21-runbook-16/`.
The microphone recording is not committed.

| Step | Result |
|---|---|
| Boot report | release `-16`, board `(test)`; no `Thermal zone name`, `Failed to register thermal zone` or EC probe failure |
| EC | `hp-omnibook-5-ec` bound at `9-0076`; hwmon (fan, four thermistors), `ec-therm1…4-thermal` zones, `platform::mute` and `micmute` all present |
| Backlight timeout | `30s` reads back and the light went off after 45 s; `always` kept it on; `3min` restored |
| Backlight level (F5) | steps 2, 1, 0 as `level` reads 2, 1, 0 (bright, dim, off) |
| Mute LEDs | EC LED 8 lights F6, LED 9 lights F9, both confirmed by eye |
| Desktop mute | speaker mute lights F6, mic mute lights F9; a muted recording is silent |
| F6 key | GNOME shows the mute icon and the LED follows |
| F9 key | **no GNOME icon**; the LED follows |
| Hotkey capture | only the keyboard HID device reported keys; every EC event read returned `00` (268 reads) |
| Rails | `vreg_l15b_e0_1p8` and `vreg_l18b_e0_1p2` enabled; USB-A and the camera enumerate |
| Stress (120 s, 12 cores) | 67 °C peak, fan to 3766 rpm, CPUs 3.4-4.0 GHz, no throttling |
| Video | `check-video.sh` (Iris, `h264_v4l2m2m`) **fails**; playback in Firefox works, in software |
| Speakers | **work** by ear; the check's tone is flaky, see below |

## Video

The decoder and encoder devices exist, but `check-video.sh` fails: every
H.264 decode through `h264_v4l2m2m` errors at once. The firmware answers the
one-core Iris configuration of `-16` with
`vDec_SetProperty_c2: Configured core 1 is not supported` and
`vDec_Start: Configured core 0 is not supported` (`Monitor=88000800`). Both
cores are refused, so the second core was not the whole problem.

The owner then played video in Firefox and it works. That is software
decoding: the `iris` interrupt count stayed at 22, all from the failed test,
and no Iris errors followed.

## Speakers

By ear the speakers work on `-16` (the owner, later the same night). The
`vdd-io not found` message is gone and both amplifiers read `Attached`. One
`SWR bus clsh detected` came about a minute after boot and did no lasting
harm.

The check's 1 kHz tone is flaky: sometimes it plays, sometimes not. The
first run, with the tone silent, matches the watch log: the bus
runtime-suspends and resumes, and at 23:22:23, as the tone started, both
amplifiers reported `UNATTACHED` and re-enumerated at 23:22:49. A tone sent
in that window is lost. This is a reading of two logs, not a proven cause.
`check-audio.sh` now plays a second of silence and waits for both amplifiers
to attach before the tones. A delay of that size after a resume is also
something a listener would notice, so it is worth a look in the kernel.

## Ubuntu 26.10 upgrade

- `libllvm21` was autoremoved, which broke `/opt/mesa-glymur` (built against
  LLVM 21) and GNOME Shell. It was installed again and marked manual.
- flash-kernel failed its trigger: it picks `vmlinuz-glymur.old` as the
  newest kernel and looks for a package of that name. It is meant for
  U-Boot-style boards; our boot chain is the USB's GRUB following the
  `vmlinuz-glymur` symlinks. Purged and held.
- `linux-generic`, `linux-image-generic`, `linux-headers-generic` and the
  `7.3.0-9` packages came in with the upgrade; removed and held. The
  `7.0.0-30` kernel and headers stay for the out-of-tree modules.
