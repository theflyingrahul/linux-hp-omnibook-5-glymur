# Runbook results, kernel `-20`, boot A (partial), November 10, 2026

`7.3.0-glymur-20` on "Ubuntu on SSD: test device tree"
(`docs/linux-runbook-20-2026-11-09.md`). Sanitized logs:
`captures/2026-11-10-k20/` (the four hardware-ID files are unsanitized on
purpose: they hold hashes of public DMI strings, no serials).

| Step | Result |
| --- | --- |
| 1 input | keyboard, touchpad, touchscreen, EC hotkeys, power key all registered |
| 2 boot report | release `-20`, model `(test)`; hardware RNG is `qcom_hwrng` |
| 2 chid | `check-chid.sh` saved `systemd-analyze chid`, stubble's `hwids.py` output (with the panel EDID `SDC4214`) and `fwupdtool hwids` for the stubble pull request |
| 4 RTC | `rtc0` registers (`rtc_qcom_glink`) but logs `0x68 failed (-110)` and `all time sources failed`; `check-rtc.sh` not run |
| 4b EC | see below; fan 2.5 krpm and four thermistors read; backlight timeout 30 s / always / 3 min write and read back (30 s and always behaved as set); F5 cycles 1, 0, 2 with the GNOME OSD each time; `platform::kbd_backlight` ignores writes as intended; both mute LEDs follow their `platform::*` writes |
| 5 audio | three SoundWire devices attached (both amplifiers and the `wcd9378` headset codec on link 3); left and right tones on the right sides; muted recording silent; **F6 and F9 showed no GNOME icon**: the function row was in function-key mode (below) |
| 9 GPU | glmark2 10881, vkcube 1000 frames, GPU at 1.35 GHz, no hangcheck |
| 10 NPU | the CDSP runs and `/dev/fastrpc-*` exist, but `fastrpc-tests` is not an apt package here (`Unable to locate package`), so no FastRPC test ran |
| not run | efivars write, USB, headset, charging, battmgr notifications, power button, suspend, boot B and C |

## Boot warnings new in `-20`

- `UBSAN: shift-out-of-bounds` in `sound/soc/sdca/sdca_asoc.c:501`
  (`sdca_asoc_populate_dapm`, shift exponent 64 on a 64-bit type), at
  module load of `snd_soc_sdca_class_function`; once per boot.
- `snd_soc_sdca.SimpleJack.0: ASoC error (-16)` reading a register, four
  times in the first ten seconds after the card appears.
- `nvme: failed to set target rate Gen5 (-11), trying rollback to Gen1`.
- `soundwire sdw:3:0:0217:0110:00:3: no matching ACPI device found, ignoring
  peripheral` and `wcd9378 ... SWFT not available`.

## check-ec.sh changed the function-row mode

The row started in action-keys mode (F7 sent volume-down, `fn_lock` read 1).
After the script it was in function-key mode, and stayed there: the
terminal received F7 escape codes while the next question was waiting
(`answer: [18~[18~...`), and the F-key capture and the audio check afterwards
show F5, F6, F9 and F11 as plain F-keys.

Why, from the script and `patches/kernel/upstream/qcom-next/0005`:

- `fn_lock_show` returns 1 when the EC's `0xBD/0x01` reply is 1, and that
  is the **action-keys** state (read 1 with F7 = volume-down; read 0 after
  Left Shift+Fn with F7 = F7).
- `fn_lock_store` follows the ABI text instead, where 1 means function
  keys: it writes the OS flag `0x80` *without* the set bit for 1, which
  clears action-keys mode.
- So `echo "$orig" > fn_lock`, the script's restore, flips the mode instead
  of restoring it. This is the same flag as the 2026-10-22 incident (clearing
  `0x80` made the row plain F-keys).
- The effect on the keyboard also trails the write by one step: F7 after
  `wrote 0` still sent F7 and F7 after the restore sent volume-down, then F7
  again on the next press. The `fn_lock` read after the restore (1) did not
  match the keyboard either.

The sysfs read now says 1. The mode on the keyboard is whatever F6 and F7
do (press them without Fn); `Left Shift+Fn` toggles it back without any
write from us. Not fixed in the series yet: show and store need the same
polarity (`show` as `reply[0] != ON`, matching the ABI text), and the
script's restore must write the value in the polarity it read.

## Open: F6 long press

Per the owner, a long press of F6 changes the keyboard backlight timeout
(an EC-side action, the same three values as `kbd_backlight_timeout`), and
GNOME shows nothing. No `EC event` line for it exists in these logs (event
logging was on, and no long press was made). To capture it: leave
`dyndbg` on, read `kbd_backlight_timeout`, long-press F6, read it again
and `journalctl -k | grep "EC event"`. If the EC raises an event the driver
can notify `kbd_backlight_timeout` and the OSD can be a desktop-side matter;
if it raises none, nothing can tell the desktop.

## Follow-up: the Fn toggle and the headset (same boot)

**Fn toggle.** After `check-ec.sh` Left Shift+Fn no longer toggled the
function row: no `EC event 0x88` and no interrupt for several minutes
(`captures/2026-11-10-k20/fn-lock-watch.txt`). Writing `fn_lock` 0 as the
owner did (action-keys flag set again) brought the media keys back, as on
2026-10-22. After a write the EC no longer reports the Fn+Shift toggle until
the flag is set again; the series needs the show/store polarity fix above
and a script that never restores through the inverted write.

**Headset (`headset-test-20261110T132742.txt`).** A 4-pole headset with a
microphone and one button: nothing played, the microphone recording was
silent (peak 0), the button sent no event, and no kernel line appeared when
the plug went in or out. What the log shows:

- The wcd9378 is `Attached` on link 3 and the headset reset line (TLMM 191)
  is high, so the codec is alive. No audio errors while the tones ran, and
  the DSP side routed `RX_CODEC_DMA_RX_0` (the script printed it on).
- **`FU 6 Channel Switch` is `off,off`** (muted) with the volume at 25088
  of 65535, and nothing in the UCM profile touches it: `HiFi.conf` has no
  headset device at all. That alone silences the headphone path. Not yet
  tried: set it on with a headset plugged in.
- **Jack detection is not working.** `Headphone Jack` reads on and `Mic
  Jack` off with nothing plugged, and the script's before/after jack state
  lines printed no values. `GE 35 Detected Mode Switch` is read-only with
  `min=0,max=0`, and reading it triggers a second UBSAN
  (`soc-ops.c:169`, `snd_soc_get_volsw` via `volatile_get_volsw` in
  `snd_soc_sdca`, shift exponent 64). The first UBSAN (`sdca_asoc.c:501`) at
  module load is the same shift: the SDCA control for the detected mode is
  built with a 64-bit width, hence `max=0`. The `ASoC error (-16)` reads of
  register `0x40c00908` fit a jack detect register being read while the
  codec is busy. So the jack-detect interrupt path and the control range
  both need the SDCA fix before the buttons or plug events can work.
- The microphone path (`TX_CODEC_DMA_TX_3`) was routed and recorded silence;
  with the jack not detected, the codec's input is probably not selected
  (`GE 35 Selected Mode` stays 0).

## Follow-up 2: unmuting the headset path, with the headset plugged in

Before: `FU 6 Channel Switch` off,off, volume 25088, `RX_CODEC_DMA_RX_0`
route off, `WSA_CODEC_DMA_RX_0` route on. Set `FU 6` on, the RX route on and
the speaker route off, then `pw-play` a 3 % amplitude 1 kHz tone, left and
right. Neither `pw-play` finished: each sat in `epoll` until killed (about
60 s), with no kernel message, no `CMD timeout`, `wpctl` answering and all
three SoundWire devices `Attached`. The stream never started, so no sound was
tested. Every control was put back to the values above. The sink PipeWire
plays to is still the speakers' (`Internal Speakers`, `MultiMedia1`) and the
card has no headset sink, so the mixer routing alone does not make a
stream run; the headset needs its own UCM device and sink, which waits for
jack detection (the SDCA `max=0` range bug above).

## NPU setup

`check-npu.sh` asked apt for `fastrpc-tests`, which does not exist. Ubuntu
has `fastrpc-support` (daemons, udev rules), `libfastrpc1` and
`libfastrpc-dev`, and no test binary. `scripts/linux/glymur-ssd/setup-npu.sh`
installs those plus a toolchain, builds `fastrpc_test` and
`fastrpc-healthcheck` from Qualcomm's source (pinned at `8f59273`) into
`/usr/local/bin`; `check-npu.sh` now runs the healthcheck first. Not built
or run here (no compiler on the laptop, `sudo` needs the owner). Known
limit: the upstream test's skeletons are Hexagon v68/v75, and this NPU is
v81 (HP's `libQnnHtpV81Skel.so`), so `fastrpc_test` may start the CDSP
session and still fail to find a matching skeleton; the healthcheck and the
session setup are the first result to read. The `hexagon-dsp-binaries-*`
packages are other boards' files and are not installed.
