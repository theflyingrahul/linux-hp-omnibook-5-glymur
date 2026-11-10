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
