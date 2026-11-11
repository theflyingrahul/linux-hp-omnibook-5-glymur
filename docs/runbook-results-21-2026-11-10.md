# Results of kernel -21, boot A (test device tree), November 10, 2026

Run so far: A1 to A6, A9. Not yet run: USB, charging, power button, suspend
(boot A), and boots B and C. Captures: `captures/2026-11-10-k21/`
(raw copies in `.work/k21-raw-2026-11-10/`, private).

| Step | Result |
| --- | --- |
| A1 input, boot report | Release `7.3.0-glymur-21`, model `(test)`. No `UBSAN`, `Unbalanced`, `CMD timeout`, `Parity error`, `GPI transfer failed` or "cannot tell the EC" in the kernel journal. |
| A2 UEFI write | The variable was written (98 to 99 visible). The script's read-back said FAIL only because `od -j4` cannot seek on efivarfs; the stored bytes match. Script fixed (`tail -c +5`). `--verify` after the next reboot is still to do. |
| A3 RTC | Still fails: opcode 0x68 times out (-110), the fallback 0x67 gets no reply and 0x65 (property 0) answers `resp_value=4294967295` (all ones, "not supported"). Reading the time returns EIO, no alarm is possible. The new request log shows the service answers the one request it understands with an error. |
| A4 EC | Fixed. `fn_lock` reads 0 while F7 is volume-down, Left Shift+Fn flips it to 1 (F7 is then F7), the EC notifies each time (6.7 s and 2.2 s after the key, i.e. the user's delay) and nothing is written. F5 cycles the `platform::kbd_backlight` LED 1, 0, 2, 1 with the GNOME OSD each time. Writing 0 is ignored. Fan 0 rpm, thermistors 37 to 39 C. |
| A4 timeout via F5 | Holding F5 for 3 s changes the backlight timeout (30 s to 3 min). The EC raises event 0x1d, the driver now notifies `kbd_backlight_timeout` (it read `3min` after the hold), and GNOME shows its OSD but with no timeout text. So the report "long F6 changes the timeout" was F5, the backlight key. F6 is speaker-mute and sends no EC event when held. |
| A5 audio | Speakers left and right correct, microphone array records (peak 32768, rms about 1600), muted recording silent, F6 and F9 LEDs and GNOME icons follow. |
| A6 headset | `GE 35 Detected Mode` now has a range (0 to 255), so `0010` fixed the control widths; both UBSANs are gone. Still: tones and playback "stuck" (no headset sink without a UCM device, as on `-20`), the recorded headset microphone is silent (peak 0), the play/pause button produced no input event, and the script's jack lines print only the control names, not their values (the script should print `amixer cget`'s value lines). |
| A9 GPU | `check-mesa.sh` ran. |
| NPU | Same as `-20`: `ARCH_VER` 32897 (v81), VTCM 8 MiB, async FastRPC supported; `fastrpc_test` fails because `/usr/local/lib/fastrpc_test` has no v81 skeletons. |

## Next

- Fix `check-headset.sh` to print the jack control values, and give the
  headset a UCM device.
- RTC: the PMIC GLink RTC gets no time from the firmware; see
  the earlier RTC analysis (commit `cf9d0ef`).
- The rest of boot A, then B and C.

## Suspend froze on the first cycle (boot A, 17:40 on November 10)

The owner ran `check-suspend.sh` (the older copy, without the pm_test pass).
The first cycle, "rtc", had no RTC alarm (the RTC has no time source), so it
was to be woken with a key. The last kernel line of the boot is
`PM: suspend entry (s2idle)` at 17:40:42; nothing after it reached the
journal, and the owner had to power off. `mem_sleep` was set to s2idle, so
this is not the PSCI "deep" path that hung on `-20`.

A pm_test pass on the next boot (`freezer`, then `devices`, after the
November 11 reboot; `captures/2026-11-10-k21/journal-kernel-pmtest.txt`)
came back by itself after 6 s and 8 s: every driver's suspend and resume
callback returned 0, including the EC, the audio codecs, USB and Wi-Fi. No
"cannot tell the EC", `Unbalanced` or slow callbacks. So the hang is after
the device callbacks: the late/noirq phase, the s2idle idle loop, or the
wake (no wake source configured with the RTC dead).

Next: `check-suspend.sh` (now installed in `~`, with the pm_test pass) and a
kernel run with the console visible (`no_console_suspend`, loglevel 8) to
see the last message; the pm_test levels `platform`/`core` are not available
for s2idle.
