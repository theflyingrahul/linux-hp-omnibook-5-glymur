# Runbook results, October 21, 2026

Kernel `7.3.0-rc4-glymur-15`, test device tree. Run from the desktop session
without keypresses or speakers; raw output in `captures/2026-10-21-runbook/`.
The previous boot's log (crash while a monitor was plugged in) was read
from the journal.

## The crash with an external display

Last lines of the previous boot, in order:

1. The hinge-side USB-C port saw a Cypress Billboard device (`04b4:5210`),
   the sign of an adapter or monitor that did not enter DP alt mode.
2. `msm_dp_display_process_hpd_high`: `panel edid read failed` (twice),
   `failed to get DP sink modes, rc=0`, then
   `DP display prepare failed, rc=-107` (ENOTCONN).
3. From 15:59:06 on, `dpu error: vblank timeout` and `enc35 frame done
   timeout` roughly every 50 ms (205 lines) until the log stops at 15:59:18.
   No oops or panic was written; the machine hung and was reset.

So the DP controller is enabled on a hot-plug whose link never came up, and
the display pipeline then commits to an encoder with no working output.
Next step is a patch (not written yet): the DP bridge must not leave the
encoder enabled after `atomic_pre_enable` fails, or HPD with a failed EDID
must not light the connector. Until then, do not plug displays into the
test tree. `check-display.sh` was not run on that boot, so there is no
alt-mode log (`ff01`).

## EC driver does not bind (explains F9, LEDs, skin temperature)

`hp-omnibook-5-ec 9-0076: probe failed with error -22` on this and the
previous boot. Cause, from the kernel log:
`thermal_sys: Thermal zone name (ec-thermistor-1-thermal) too long, should
be under 20 chars` / `Failed to register thermal zone ...: -22`. The hwmon
registration of the EC fails in the test tree's skin-temperature zones.
Consequences seen on this boot: no `ec-*` thermal zones, no EC hwmon, no
`platform::mute`/`micmute` LEDs, no EC interrupt, and the EC's input device
disappears. Fix (not yet booted): the zones are renamed `ec-therm1…4-thermal`
(17 characters) in `dts/qcom/mahua-hp-omnibook-5-bf1xxx-test.dts` and the
doc. Needs a DTB rebuild and install, then a reboot.

Read-only EC probes (driver unbound): `0x43` returns `0x00`, `0x44` returns
six zero bytes, event register `0x05` returns `0x00`. GPIO 66 idles high
with pull-up; the DT interrupt is `<&tlmm 66 EDGE_FALLING>`. Zeros may only
mean the EC answers these commands late or not at all; repeat after the
driver binds before drawing a conclusion. Steps 4b and 4d (edges on F9,
hidraw reports) need keypresses.

## Other steps

| Step | Result |
| --- | --- |
| 2 USB-A | OK: stick on the 10000M bus, 0 `Cannot enable` lines. |
| 3 audio names | OK: "Internal Speakers", "Microphone Array", card "Built-in Audio". Both `ctl-led` lists bound (speaker 88, mic 89). Sound output, muted-recording silence and F6/F9 behavior not tested (need ears/keys). `Built-in Audio` is the device description, not the expected "Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio Device": the WirePlumber device rule did not apply. |
| 4 F9 | Blocked by the EC probe failure above. |
| 5 video | Fails: `video_cc_mvs1_gdsc status stuck at 'off'`, `gdsc_toggle_logic` warning, `qcom-iris: power on failed` on every open (`v4l_id`, and the earlier decode attempt). No firmware authentication was reached. |
| 6 display | Crash, above. |
| 7 camera | RGB node `/dev/video2`: 640x480 colour frame; IR node `/dev/video4`: 400x400 grey frame (`GREY`, 15 fps). Both work. Touchscreen and Bluetooth audio need hands. Controller `hci0` is up. |
| 8 cluster idle | Works: `power-domain-cpu-cluster0` state S0 used 65120 times (13489 rejected). |
| 9 skin zones | Not testable (zones failed to register). 120 s of `stress-ng --cpu 12`: hottest zone 64.7 C, CPUs held 3.4 and 4.0 GHz, no throttling. |
| 9 SPEL | Idle / 12-thread load (W): sys 7.9 / 27.2, soc 1.7 / 15.7, cl0 0.1 / 4.4, cl1 0.5 / 10.1, wlan 3.8 / 3.3, igpu 0.4 / 0.5, dram 0.3 / 0.3. Power limits read 0 for `sys`/`soc` and "No data available" for the other zones: the firmware left no limits set that the driver can read. |

## Confirmed by hand afterwards

Touchscreen works; Bluetooth A2DP playback to headphones works.
