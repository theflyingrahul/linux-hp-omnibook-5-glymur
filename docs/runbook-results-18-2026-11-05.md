# Runbook results, kernel `-18`, partial, November 5, 2026

Boot of `7.3.0-rc6-glymur-18` on "Ubuntu on SSD: test device tree"
(`docs/linux-runbook-18-2026-10-23.md`). Only the steps that need neither
root nor the owner's hands were run; raw output in `captures/2026-11-05-k18/`.

| Step | Result |
| --- | --- |
| 0 install | already on `-18`; `plymouth-job-monitor` disabled; the `52-no-v4l2-monitor` WirePlumber file is gone |
| 1 input | keyboard, touchpad, touchscreen, EC hotkey device and power key all registered; no `Unsupported SE source clock` or `Failed to find SE source clock` |
| 2 boot report | release `-18`, model `(test)`; no `qcom-iris` or `rtc-pm8xxx` lines; no `CMD timeout` at boot |
| 3 audio bisect | three `systemctl --user restart wireplumber` runs, 55 s apart, with a 440 Hz tone playing (21:56, 21:57, 21:58): no `CMD timeout`, no `Parity error`, `wpctl status` answered each time, both WSA884x amplifiers `Attached` afterwards. Nothing in the kernel log for the whole boot matches `CMD timeout\|Parity\|clsh\|Oops\|BUG\|WARNING\|lockup`. Three restarts is a small sample against the `-17` stalls, which came after 815 s |
| 4.1 EC interrupt | `hp-omnibook-5-ec` on GPIO 66 shows 2 interrupts, unchanged over 10 s |
| 4.5 GPU | `check-mesa.sh` twice: glmark2 score 10713 and 10698 on `Adreno (TM) X2-85`, OpenGL ES 3.2 Mesa 26.3.0-devel; the GPU clock sat at 1.35 GHz during the runs; `vkcube` 1000 frames, exit 0; no hangcheck or GPU error in the kernel log |

## Not run (needs root or the owner)

`check-audio.sh` (asks before every sound), 4.2 `check-hotkeys.sh` (F9, F11),
4.3 `charging-watch.sh` (charger unplug/replug), 4.4 USB devices in each
port with `check-usb.sh`, 4.6 the power button, and step 5 only if F9 sent
nothing. Battery read 85 %, discharging, AC offline at the time of the check.

## Added after the owner ran the root steps

`audio-test-20261105T220207.txt`, `hotkeys-20261105T220408.txt`.

| Step | Result |
| --- | --- |
| audio | both amplifiers `Attached`; left and right tones heard on the right sides; muted recording `SILENT, OK` (peak 0); software mute lit the F6 LED for the speakers and the F9 LED for the microphones |
| F6 | GNOME showed the speaker-mute icon |
| F9 | arrives as `KEY_MICMUTE` (248) from the EC input device `HP OmniBook 5 EC hotkeys`: the EC event line works on `-18` (issue #11). The owner's answer to which GNOME icon appeared was a bare `y`, so the icon is not recorded |
| other keys | F3/F4 brightness, F6 mute, F7/F8 volume, F10 play/pause arrive from the keyboard; F1, F2, F11 (LCtrl+F17), F12 (SysRq) and the Copilot key (Meta+LShift+F23) arrive as key combinations; F5 sends nothing; Fn+F1…F12 give plain F1…F12; Fn alone sends scancode 54 |
| charging | **not tested on this kernel.** No `charging-watch` log exists after 2026-09-30, and the journals of the previous two boots (both `-18`) contain no plug or unplug events, so the test the owner remembers left no record |
| USB devices, power button | not run |

## Logs

`captures/2026-11-05-k18/`: kernel journals of this boot and the two before
it, `dmesg`, the boot report, the audio, hotkey and Mesa checks and the GPIO
debugfs listing. They went through `scripts/linux/sanitize-log.sh`: MAC
addresses (including the access point's), UUIDs and partition UUIDs, USB
serial numbers, the user name, e-mail and IP addresses are replaced. The
5 s microphone recording is left out, and the full systemd journal stays
private in `.work/k18-raw-2026-11-05/` (unsanitized kernel journals too).
