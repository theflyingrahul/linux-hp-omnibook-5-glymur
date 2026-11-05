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
