# Display Lab, Second Run: September 28, 2026

Second run of the lab from `~/glymur-lab-kit` on the display-lab device tree
(kernel `7.3.0-rc2-glymur-3`), with the run-1 fixes (`docs/display-lab-run1-2026-09-28.md`).
Private logs: `.work/lab-run2-2026-09-28/`.

## Result: phases 1 to 4 complete; the laptop hung at the start of phase 5

- **Phases 1 to 4 ran clean.** With `scmi-cpufreq` skipped, phase 4 finished
  (`40-power.txt`, 12 KB): `qcom_battmgr`, `ucsi_glink` and
  `pmic_glink_altmode` were already bound, the four `qcom-battmgr-*` and two
  `ucsi-source-psy` supplies are present, and `/sys/devices/system/cpu/cpufreq`
  is empty. The firmware eDP snapshot is identical to run 1 (2 lanes, 2.7 Gb/s).
  Bluetooth was skipped because HP's pair is already installed. This confirms
  that loading `scmi-cpufreq` was what hung run 1.
- **The hang.** The last journal line of the lab boot, about 12 s after the
  lab started, is `gdm.service: Stopped` at 300.988 s: phase 5 had begun by
  stopping the desktop. Nothing later reached the disk: no
  `MARK v0-baseline`, no kernel message from the overlay, no phase-5 line in
  `lab.log` (it ends at the phase-4 line, its tail lost). No oops or panic
  either, `/var/lib/systemd/pstore` is empty and the machine has no hardware
  watchdog (`/sys/class/watchdog` is empty), so a hang stays a hang until
  the power button.
- **Where in phase 5 is not known.** Between the desktop stopping and the
  first eDP attempt the script does `sleep 5`, `chvt 1`, `echo 0x106 >
  /sys/module/drm/parameters/debug`, then writes the display overlay
  (dispcc, MDSS, the DP3 PHY and the panel supply appear at once). Any of
  them is a candidate; the overlay is the likeliest, because it makes msm and
  dispcc probe at runtime and touch the display registers.
- Both hangs so far are silent: a stuck bus access is the usual cause
  (a register read on an unclocked block never returns), but that is a guess.

## What was changed to find out

`glymur-lab-run.sh`: every `say` line now also goes to the kernel log, runs
`sync` and `journalctl --sync`, and phase 5 is split into steps 5.1 to 5.5
(stop desktop, desktop stopped, console, DRM debug, apply overlay, overlay
applied), each announced on the screen (tty1) and flushed. The last step
shown on the screen and the last line in `lab.log` after the next hang name
the culprit. The kit at `~/glymur-lab-kit` has the new script and checksums.

## Next

- Re-run `sudo bash ~/glymur-lab-kit/start-lab.sh` and note **the last
  "step 5.x" line on the screen** when it stops (a photo is enough).
- Firmware link and lane finding (2 lanes at 2.7 Gb/s against our 4 lanes)
  is unchanged; `data-lanes = <0 1>` is worth testing in the full DT
  independent of the lab.
