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
| F9 key | **does nothing**: no GNOME icon, the microphone is not muted and the LED stays off (`check-audio.sh` read `micmute 0` and the source unmuted after F9) |
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

## Hotkeys, EC interrupt, RTC and charging (later the same night)

The 30 s hotkey capture (F6, F9, F11, F5, Fn) saw two key events, both on the
keyboard's own HID device:

- F6 arrives as `KEY_MUTE` (code 113), and it auto-repeated while held.
- A second press arrives as **Ctrl + `KEY_F17`** (usage `0x7006c`). The
  mic-mute key, F9, is the likely sender; this is inferred from the order
  of presses, not tested alone. Nothing in GNOME binds Ctrl+F17, which would
  explain why F9 neither shows an icon nor mutes the microphone; the LED
  follows only a software mute, not the key.
- F11, F5 and Fn produced nothing on any device. F5 (backlight) is handled
  inside the EC, so that is expected.

The EC event line (GPIO 66) fires about nine times a second even when idle
(87 interrupts in 10 s), and every event read returns `00`, "no event". Key
presses did not change the byte. That is a constant wake-up load, and either
the EC is pulsing the line for another reason or the edge is being
re-triggered by the read. Open.

There is no RTC device (`/dev/rtc*`, `timedatectl` says "RTC time: n/a"), so
the clock restarts from the last saved time at every boot, as seen in the
journal (boots stamped 2026-10-02) until NTP corrects it.

At 23:39 both xhci controllers of one USB-C port were removed (a role
switch, consistent with unplugging a cable). The battery read `Charging` at
74 % while the AC supply and the USB-C source both read `online=0`
afterwards, so the status was stale for a moment or the charger had just
gone.

## Battery-manager notifications (`check-battmgr-notify.sh`, 60 s, plug and unplug)

`qcom_battmgr_state_callback`, the function `backports/0023` adds for the
Glymur firmware's state notifications, was called **0 times**. The regular
`qcom_battmgr_callback` ran 2,076 times, in bursts (up to 257 calls in a
second, median 17) with a once-a-second beat between them. So on this laptop
the firmware did not send the state notifications on a plug or unplug, and
the premise of that patch is not confirmed here; the battery still changed
state, through the regular path. The status read `Discharging`, `Charging`
and `Discharging` again at 10 s samples while `ac` and `usb` stayed `0`
(battmgr's AC and USB supplies do not follow USB-C charging; the UCSI source
supply does). No timeout or hang appeared. Raw log:
`captures/2026-10-21-runbook-16/battmgr-notify-20261021T233919.txt`.

Correction: an earlier line of this note said the F9 LED follows the key. It
follows a software mute and the manual LED test, but pressing F9 changed
nothing (the audio check's own readback after F9: source not muted,
`platform::micmute` 0, 48 EC interrupts in that window).
