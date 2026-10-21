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

## Function-key map (`check-hotkeys.sh`, 2026-10-22)

One key at a time, from the kernel's input events
(`captures/2026-10-21-runbook-16/hotkeys-20261022T000907.txt`). This replaces
the guess above that F9 sends Ctrl+F17.

| Key on its own | What the kernel sees | GNOME |
|---|---|---|
| F1 | Meta+P, twice | display switcher (Super+P) |
| F2 | Meta+Ctrl+Alt+Shift+Space | nothing bound |
| F3, F4 | `BRIGHTNESSDOWN`, `BRIGHTNESSUP` | brightness |
| F5 | **nothing** (the EC runs the keyboard backlight itself) | |
| F6 | `KEY_MUTE` | speaker mute, LED follows |
| F7, F8 | `VOLUMEDOWN`, `VOLUMEUP` | volume |
| F9 | **nothing, on any device** | no mic mute |
| F10 | `PLAYPAUSE` | media |
| F11 | Ctrl+F17 | nothing bound (HP's programmable key) |
| F12 | `SYSRQ` (Print) | screenshot |
| Fn alone | nothing | |
| Copilot | Meta+Shift+F23 | nothing bound |
| Fn+F1…F12 | plain F1…F12 (59-68, 87, 88) | |

So the earlier notes were wrong twice: F9 does not send the HID Mute that F6
sends (at least not on `-16`), and the Ctrl+F17 was F11, not F9. F9 reaches
the system only as the EC's event `0x11`, which the driver maps to
`KEY_MICMUTE` and which never arrives.

HP's AML reads the event the same way the driver does: `\_SB.IC10.INTR` reads
the data byte of register `0x05` (the generic serial bus reply carries a
status and a length byte in front) and writes `0` back. The EC's line still
falls about every 118 ms with the driver unbound and the byte reads `00`.
HP's AML never writes the reference "enable events" command `0x35`. The OS
flags `0x80`, `0x81`, `0x82` and `0x84` (mailbox command `0x01`) are written
by named methods (`APET`, `SCET`, `MSET`, and `SMLS` for `0x84`); the driver
sends only `0x84`. Whether `0x80` or `0x81` gate event delivery is unknown.

## OS-state flags do not switch on F9 (`ec-hotkey-flags.sh`, 2026-10-22)

HP's AML has `APET` (mailbox command `0x01`, flag `0x80`) and `SCET` (`0x81`)
that nothing in the tables calls, so HP's Windows driver must. With the EC
driver unbound, `0x80`, `0x81` and both together were set one at a time (the
EC answered each with status `0xe0`, done), and register `0x05` was polled
every 30 ms while F9 and F11 were each pressed twice, after a baseline
without any flag. **Zero non-zero reads in every trial**, flags and baseline
alike. The flags were cleared afterwards, the driver rebound and the LED
triggers restored. Log: `captures/2026-10-21-runbook-16/ec-flags-*.txt`.

The keyboard's HID report descriptor has a vendor collection (usage page
`0xff85`) with feature reports `0x0a` (8 bytes) and `0x0b` (32 bytes); both
read all zeros through `hidraw`. What they carry is unknown.

What remains: the reference "enable events" command `0x35` (HP's AML never
writes it), HP's `HPIC0003` application driver and `HPIC0005` mute-LED device
(evidence from Windows: how it sets up hotkeys), and the vendor HID
collection.

## The stuck event in register 0x00 (2026-10-22)

HP's AML reads the event through the field `CMD5`, which starts at offset 0,
so the register is `0x00`, not `0x05`. A read-only scan of registers
`0x00`-`0x0f` found `0x00` = `0x30` (the reference code for "fan 1 status
change") and everything else zero. Writing `0` to register `0x00`, as HP's
AML does to acknowledge, cleared it, and the line on GPIO 66, which had
fallen every 118 ms, then stayed quiet (checked with `gpiomon` for 6 s).
So the nine interrupts a second were one old event, never acknowledged
because the driver acknowledges register `0x05`.

(A reading I took at the time, "0 interrupts in 10 s" from
`/proc/interrupts`, was an empty read: after an unbind and rebind of the
driver the EC interrupt is no longer requested and the line is missing from
the file until the next boot. The `gpiomon` result is the valid one. Also
open: why a rebind loses the interrupt.)

With the line quiet, `ec-event-capture.sh` saw **no falling edge for any
key**: F9 (twice), F11, F6, F5 and Fn alone (`ec-events-20261022T002306.txt`),
not even F5, whose event `0x0d` HP's AML expects. So the EC raises no hotkey
events in its present state. Next: a second pass with the reference command
`0x35` ("enable SCI events"; the driver for Qualcomm's EC writes `1` to it
at probe), which the script now offers.

## Flag 0x80 is the action-keys mode (2026-10-22)

After the flag experiments the function row sent plain `F7`/`F8` (codes 65 and
66) instead of `VOLUMEDOWN`/`VOLUMEUP`. `ec-hotkey-flags.sh` had cleared flag
`0x80` (APET) at the end of each trial and at exit. Setting `0x80` again
(mailbox command `0x01`, sub-command `0x80`) brought the media keys back
(confirmed by the owner and a key capture), so **APET is the action-keys
mode**: set, F1-F12 send their media functions; clear, plain F-keys. The
state is in the EC and survives the driver being unbound.

The script was cleared both flags and left them that way; `0x80` is now
restored and the script leaves it set. `0x81` (SCET) was also cleared
(`0x01`) and is not restored: its original state is not known and nothing
visible depends on it so far. Lesson: read a state before changing it; no
register is known to read back a flag.
