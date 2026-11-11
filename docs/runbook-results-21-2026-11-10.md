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

## Suspend, second attempt (November 11, 14:45): four cycles came back, the drain cycle froze

`captures/2026-11-10-k21/suspend-test-20261111T144533.txt`. The pm_test pass
(`freezer`, `devices`) came back after 6 s and 9 s. Then, in s2idle:

| Cycle | Wake | Result |
| --- | --- | --- |
| rtc (no alarm possible) | key on the keyboard (hid-over-i2c IRQ) | resumed; power LED breathing; screen, keyboard and touchpad back |
| lid (charger unplugged and replugged while asleep) | lid switch (GPIO 92) | resumed |
| button | power key (`pmic_pwrkey`) | resumed |
| lid-ac, 2 minutes | power key | resumed (the lid on AC did not wake it, as expected) |
| drain (10 min, on battery, lid closed) | lid open | **froze** |

So the first-cycle hang of 17:40 on November 10 was the old script (no
pm_test, no wake plan); with the key as the wake source suspend works. The
sleep itself is still shallow: `cxsd`, `aosd` and `ddr` stayed at 0 in every
cycle, and the battery fell at 2.3 to 5.6 W (average about 4.5 W), the
"only the CPUs slept" state of `-20`.

The drain cycle: the journal's last line is `PM: suspend entry (s2idle)` at
14:52:38, nothing after. The owner reports no power LED (it breathed in the
other cycles), no reaction to a press or a long press of the power button,
and a forced power cycle. The battery was not flat: 57.0 Wh at the start of
the test, 55.5 Wh (91 %) at the next boot, about 1 Wh over the 10 minutes,
so the machine kept drawing power (roughly 5 W) until the cycle. The
difference from the four good cycles is that this one entered suspend on
battery (charger unplugged before the lid closed), and was left for 10
minutes. Hypotheses, not tested: the EC (standby entered, LED off) stops
answering when the machine is on battery in standby for minutes; the EC's
standby state needs the exit write the retry covers, but the lid-open wake
came to nothing; or the SoC wedged in a state the power button cannot
reach (button wake is a PMIC interrupt).

Next: repeat the drain cycle on AC (charger in, lid closed 10 minutes,
lid open) to separate "long sleep" from "on battery"; with `--console`
and the console on a text VT; then with `hp_omnibook_5_ec` unloaded
(no standby message to the EC) if it still freezes. The drain figure
without a working sleep depth is not yet useful.

## USB, boot A (November 11, 15:05, nothing plugged in the USB-C ports)

`captures/2026-11-10-k21/usb-test-20261111T150531.txt`. USB-A (right port,
`a000000.usb`): the installer stick enumerates at SuperSpeed (5000M, mass
storage). At boot it took five attempts with `error -71`, the flakiness of
`-18`; it works once up. Camera (`a200000.usb`) fine. USB-C: both
controllers (`a600000`, `a800000`) are bound, both ports in device role with
no partner, because nothing was plugged in; the mouse and the USB-C stick in
each USB-C port are still to do (they need hands).

## Power button, boot A (November 11, 15:14 to 15:16)

The key works awake: `pmic_pwrkey` (`event9`) delivers `KEY_POWER` press and
release (0.67 s apart in a raw capture), `systemd-logind` logs "Power key
pressed short" for each press, and PON's interrupt registers are as the
driver sets them (edge, both polarities, enabled). `gnome-shell` logs
`endSessionDialog` for each short press, but the owner sees the power-off
dialog only for a 2 to 3 s hold, not for a quick press, with
`power-button-action` = `'interactive'`. Kernel side passes; the quick-press
dialog is a GNOME 51 behaviour not explained yet. (My first interrupt-count
reads of 0 were mistimed.)

## Keyboard backlight: OSD and the quick-settings slider (November 11)

- Holding F5 for 3 s now shows GNOME's timeout OSD (the shell extension of
  `e9e2ec4`): confirmed by the owner.
- GNOME's quick-settings keyboard-brightness slider does nothing. Expected:
  the `platform::kbd_backlight` LED has no set callback, so the LED core drops
  the writes. A callback cannot help: the EC has no command that sets the
  level. `WMID.SBKT` is `HQEX(0x05, n)`, which sets the timeout (so the
  September 30 "writes accepted, nothing visible" result is explained), the
  level is only read (`0x05`/`0xff`, event `0x0d`/`0x1d` from F5), and no HP
  Windows binary mentions a backlight (`docs/keyboard-backlight-2026-10-23.md`).
  Open for the Windows side: a bus trace of Windows changing the level, or a
  newer EC firmware. No change made on Linux.

## Power button, raw evidence

`power-key-capture.txt` (press/release of `KEY_POWER`, 0.67 s),
`pon-registers-0x1300.txt` and `pon-rt-sts-samples.txt` (PMK8350 PON
interrupt registers: edge, both polarities, bit 7 enabled; real-time status
bit 7 went high during a hold), `journal-user-session-power-button.txt`
(logind "Power key pressed short" and gnome-shell `endSessionDialog` for
every press).

## What is left of the runbook

Boot A, not run or not finished: USB-C ports with the mouse and the USB-C
stick (A7), headset again with the new script (A6), charging and
battery-manager notifications (A8, need the adapter), the drain cycle and
`--sync-state` suspend (adapter), `--console` suspend. Boot B (A/V device
tree, GRUB edit, WirePlumber file first): B3 `check-efivars-write.sh
--verify` (the variable from A2 is waiting), B4 boot options without
`$cmdline`, B5 suspend without `pd_ignore_unused`, B6 `check-video.sh
--mahua` (first trial: partial-data buffer for AV1 only), B7 external
displays last (the machine crashed at this step on `-20`). Boot C: the
daily entry (model without `(test)`, speakers and microphones, F6/F9,
USB-C stick at SuperSpeed).

## Boot B, A/V device tree without `$cmdline` (November 11, 15:22)

The boot worked on the first try: model `(test, A/V)`, keyboard, Wi-Fi, desktop.
Captures: `video-test-20261111T152603.txt`, `efivar-write-20261111T152522.txt`,
`journal-kernel-boot-av-k21.txt`, `cmdline-av.txt`, the boot report.

| Step | Result |
| --- | --- |
| B3 UEFI write | The variable written in A survived the reboot unchanged (attributes 0x7, same 32 bytes): `PASS`. The script's delete failed (`rm`: Invalid input): the firmware refuses to delete a variable this way; the test variable `GlymurWriteTest-…` stays in the store. Needs a different delete (write with an empty payload) in the script, or accepting the leftover. |
| B4 boot options | Command line has no `clk_ignore_unused`, `pd_ignore_unused` or `arm64.nopauth`. `clk: Disabling unused clocks` and `PM: genpd: Disabling unused power domains` are logged; pointer authentication works (`paca`/`pacg` on all 12 CPUs); Wi-Fi connected. At boot Iris logs `power on failed` / `core init failed` with a `gdsc_toggle_logic` warning (first open by `v4l_id`). |
| B6 video, `--mahua` | The new first trial (partial-data buffer kept to AV1, `diag_partial_av1_only=1`) did not decode: ffmpeg was killed (137) like the other trials, and the firmware's "Buffer type 5 should be used for AV1 only" error is gone in it, so that complaint was not the stall. The same settings without the option (trial 2) still log the complaint and stall. Trials 3 to 5 then fail at `can't configure decoder` (exit 234), the core being wedged after the stall. Every trial also logs `power control was 0x3, status 0x3 after release (timed out, bit 0x10)`. |
| B5 suspend without `pd_ignore_unused` | Not run (suspend: the 10-minute battery cycle froze in A; owner asked to leave it). |
| B7 external display | Not run. |

## Review on the development machine (November 11)

- **NVMe link-rate switching.** `nvme nvme0: failed to set target rate Gen5
  (-11), trying rollback to Gen1` appears 482 times in the boot that froze,
  every one to two seconds. It comes from qcom-next's FROMLIST "nvme: Add
  adaptive PCIe link rate switching" (Hygon/Kylin, `565e1c0bc2d6` and two
  follow-ups; not in mainline), enabled in our config
  (`CONFIG_NVME_SPEED_SWITCH=y`). Each attempt freezes all NVMe I/O and
  retrains the PCIe link, fails, and retrains back. Its timer queues the
  work on the system workqueue, which is not frozen for suspend, and
  `nvme_suspend()` does not stop it, so a retrain can reach a PCIe host that
  has already suspended. A retrain ran within a second of every suspend
  entry of that boot, the five that resumed included, so it does not
  explain why the drain cycle alone froze; it is a race that can hit any
  cycle. It is off from now on: `install-from-usb.sh` installs a udev rule
  that writes 0 to `/sys/class/nvme/nvme*/speed/enable`, `check-suspend.sh`
  turns it off before the cycles, and `-22` builds without it.
- **Shallow sleep.** The blocker snapshot is taken awake, so it lists the
  normal awake votes (`bi_tcxo` prepared 29 times, the GPU's `gpu_cc_cxo_clk`,
  the Bluetooth UART's QUP vote); what stays on in sleep needs the
  `--sync-state` run. The script also printed a shell error per clock: this
  kernel has no `clk_consumers` file (fixed).
- **UEFI delete.** efivarfs deletes with attributes 0, which Qualcomm's
  TrustZone variable service refuses (`EINVAL`; the Linux driver passes a
  size-0 write through). `check-efivars-write.sh` now falls back to writing
  only the variable's 4-byte attribute header (`SetVariable` with its own
  attributes and no data, a delete in the UEFI specification), and
  `--delete` removes the test variable left by boot B.
