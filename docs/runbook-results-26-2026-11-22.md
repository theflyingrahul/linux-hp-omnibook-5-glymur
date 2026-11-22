# Kernel -26 results, November 22, 2026

`7.4.0-rc3-glymur-26`, the first kernel on Linux 7.4 to be booted (`-24` and
`-25` were not), was installed from the USB stick on November 21 and booted
four times on November 22: twice on the test device tree (model `(test)`)
and twice on the A/V test device tree (`(test, A/V)`). The tests follow
`docs/linux-runbook-26-2026-11-21.md`. Raw logs, sanitized, are in
`captures/2026-11-22-k26/`; the PMK8850 SDAM dump and the headset register
snapshots are private, in `.work/k26-2026-11-22/`. The RTC still does not
work, so a boot report written before NTP carries the pre-NTP time in its
name (`boot-20261002T230654-9c860a15.txt` is the second A/V boot).

| Step | Result |
| --- | --- |
| A1 basics on 7.4 | pass: the panel (the ported eDP fix), input, Wi-Fi, speakers, GNOME on the GPU (glmark2 14338). One new deferred probe |
| A2 clock | the PMK8850 counter runs at 1 Hz but no SDAM word turns it into wall time: the device-tree route is ruled out |
| A3 EC events | pass: no failed event read or clear, every key worked at the end |
| A4 headset | the codec binds on 7.4. The left/right swap is upstream of SoundWire. Jack detection, the microphone and the button still fail. Plugging in started an alert storm |
| A5 USB | the `i2c5` scan finds no repeater; USB-C SuperSpeed and full speed on both ports; USB-A stress 20 of 20, **but with Linux's PHY values**: the test tree lost HP's in `-25` |
| A6 charging | pass |
| A7 suspend | four cycles came back, and **the SoC reached CX, AOSS and DDR sleep for the first time** (110 s of 157 s). The drain cycle on battery froze, as on `-21` |
| B A/V tree | pass for input, Wi-Fi, sound, brightness, camera and GPU (glmark2 13765). The camera app needed a WirePlumber restart; no shutter sensor is visible. Iris boots its firmware, but decoding fails; `check-video.sh --mahua` deadlocked the apps SMMU. External display not run |
| C daily entry | not run yet |

## A1. The basics on 7.4

- Boot report: `7.4.0-rc3-glymur-26`, model `HP OmniBook 5 Laptop 16-bf1xxx
  (test)`. The panel came up, so the eDP v8 power-on fix ported to 7.4's
  eDP PHY code works. Keyboard, touchpad, touchscreen and Wi-Fi work; the
  owner checked the speakers by hand.
- `check-mesa.sh` (`mesa-test-20261122T103232.txt`): glmark2 14338,
  `vkcube` 1000 frames on the Adreno X2-85, `gnome-shell` on
  `/opt/mesa-glymur`. The `gen80100_sqe.fw` load errors are the usual
  pre-rootfs attempts; the firmware loads 10 s later.
- `UBSAN|Unbalanced|Oops|BUG:|WARNING:`: nothing.
- **New warning:** `c426000.spmi:pmic@7:temp-alarm@a00: deferred probe
  pending`. In 7.4, `glymur-crd.dtsi`'s pattern gives PMH0110 temperature
  alarms an `io-channels` reference to the PMK8850 ADC
  (`qcom,spmi-adc5-gen4`, `pmk8850_vadc`), and our config does not build
  its driver (`CONFIG_QCOM_SPMI_ADC5_GEN3`, which matches gen4 too). The
  fix is that config option. Harmless until then: the alarm only
  throttles at the PMIC's own limits.
- Also new on 7.4: `qcom,fastrpc ... reserved memory is beyond device's set
  DMA address range` (the ADSP's FastRPC heap); FastRPC still binds.
- Speaker clips played by `pw-play` (under a second each) were not heard;
  the owner's own test was. A short-stream start-up loss, not followed up.

## A2. The clock

`check-rtc.sh` (`rtc-test-20261122T103711.txt`), run unattended with
chrony synchronised:
- `rtc0` (`rtc-qcom-glink`) fails as on `-23`: `0x68` times out, `0x65`
  acks with `0xffffffff`, the 20 s alarm cannot be set.
- `rtc1` is the PMK8850 RTC (`rtc-pm8xxx`, `c426000.spmi:pmic@0:rtc@6100`).
  Its counter read `0x008bd607` (9164295 s, "1970-04-17 01:38:15") and
  advanced 58 s in 59 s of wall time. Its zero is 2026-08-08 03:28:59 UTC:
  wall time = counter + 1786159741 s.
- No word in the sixteen SDAM blocks (`0x7000`–`0x7fff`) brings the counter
  within an hour of UTC or IST.

By `docs/rtc-2026-11-21.md`'s decision table that is "neither": the ADSP
keeps the offset where Linux cannot read it, so the next step is the ABD
time request (offset `0x30200`). The offset itself is recorded here so a
later boot (or one after Windows) can show whether it changes.

## A3. EC events

The owner pressed F5 (also held), F6, F9, the brightness keys and Left
Shift+Fn repeatedly. `cannot (read|clear) EC event`: nothing; every key
worked at the end.

F6 and F9 later stopped muting, after A4. Cause: `check-headset.sh` stops
`pipewire-pulse.socket`; `gsd-media-keys` logged "Unable to get default
sink/source" when the socket closed and never reconnected. Killing it (its
unit restarts it on failure) brought both keys back. `check-headset.sh`
now does that itself when it restores PipeWire.

## A4. Headset (`headset-test-20261122T105546.txt`)

- **Binding:** `wcd9378 sdw:3:0:0217:0110:00:3` binds on 7.4 with the
  `qcom,sdca-compliant` node, which is what `-26` was for. "SWFT not
  available", as since `-21`.
- **Playback:** the left and right tones of the first test came out on the
  right sides; −20 dB was clearly louder than −40 dB, but the −40 dB
  "left" tone came out on the right.
- **The six-stream left/right test:** right, right, right, left, left,
  right for six streams of the left tone. The codec registers were the
  same for every stream ("registers that tell the two apart: 0"), so the
  swap happens before SoundWire: in the codec DMA or the RX macro. The
  snapshots are in `.work/k26-2026-11-22/headset-swap-20261122T105644/`.
- **Jack detection:** `Headphone Jack` and `Mic Jack` stayed `off` through
  plug and unplug.
- **Microphone:** `SWR_MIC0` read full scale (peak 32767), several other
  inputs failed with `-EIO`, and the playback was white noise. On `-23` the
  microphone recorded on `SWR_MIC0`.
- **Button:** play/pause pressed, no event.
- **Alert storm (new):** from 10:56:01, about when the headset was plugged
  in, the headset bus (`7630000.soundwire`) logged read-FIFO underflows,
  failed transfers to the codec (`trf on Slave 1 failed:-5`) and
  `Slave 1 alert handling failed: -5`, then `wcd9378 ... Reached MAX_RETRY
  on alert read` about 50 times a second until the reboot (17,937 lines by
  11:02; `journal-kernel-headset-storm-1055.txt`). The WSA bus
  (`6c80000`) logged underflows at the same time. The failing alert reads
  are the likely reason the jack state never changes. The next boot had
  none.

## A5. USB

- **USB-A repeater scan** (`usb-test-20261122T103652.txt`): `i2c5` is
  `i2c-10`; nothing answers at `0x40`–`0x4f`. Not a PTN3222 on this bus. By
  `docs/usb-a-repeater-2026-11-21.md`, the next step is the UEFI firmware's
  USB initialisation.
- **USB-C** (`usb-test-20261122T105851.txt`, `...105920.txt`): the boot
  stick at 5000 Mb/s on connector 0 (`a600000`) and on connector 1
  (`a800000`); the Dell receiver enumerated at 12 Mb/s on both, but behind
  a USB 2.0 hub, so the port's own full-speed path was not tested.
- **USB-A SuperSpeed stress** (`usb-test-20261122T103831.txt`): `back at
  SuperSpeed 20, at high speed 0, gone 0 of 20; link errors in all: 0`,
  1 GiB at 143 MB/s. The log shows `HP PHYC overrides in this device tree:
  none`: commit `d65b31f` (`-25`) deleted the `&usb_2_qmpphy` override
  from the test tree together with the repeater supplies it moved, though
  the file's header still says the test tree keeps HP's USB-A values. This
  run therefore repeats boot C of `-23` (Linux's values), not the A/B
  comparison. Restore the override for the next kernel.

## A6. Charging (`charging-watch-20261122T110451.txt`)

Three plugs: connector 0, connector 1, connector 0. Each came up as a
Type-C current advertisement, then a PD contract at 3.25 A about 0.5 s
later, and `Charging`; each unplug returned to `Discharging`. `ac` and
`usb` stay `0`, as known.

## A7. Suspend (`suspend-test-20261122T111121.txt`)

Second test-tree boot, from a text console. pm_test `freezer` and
`devices` came back. Then, in s2idle, all with the charger in:

| Cycle | Wake | Asleep | `cxsd` / `aosd` / `ddr` |
| --- | --- | --- | --- |
| rtc (no alarm possible) | key | 18 s | +1 entry each, ~0.6 s |
| lid | lid (GPIO 92) | 32 s | +4 entries, ~1.7 s |
| button | power key | 18 s | +1 entry, ~1 s |
| lid-ac | lid | 157 s | **+51 entries, 110 s** |

This is the first time any of the three counters has moved: every cycle
on `-20` to `-23` logged `entries +0`. The SoC now reaches CX collapse,
AOSS sleep and DDR self-refresh for 70 % of a 2.5-minute sleep. Every
cycle came back with the screen, keyboard and touchpad. The owner saw the
power LED breathing in two cycles, and off on opening the lid in the
last; the keyboard backlight was off. The battery figures are not
meaningful, because the charger was in.

**The drain cycle froze.** With the charger unplugged and the lid closed
for 10 minutes, the machine did not come back and needed a forced power
off. The journal's last line is `PM: suspend entry (s2idle)` at 609.995 s
(`journal-suspend-freeze-drain.txt`). This is `-21`'s failure exactly: the
only cycle that freezes is the one entered on battery and left for
minutes. `-21`'s next step still stands: the same 10 minutes with the
charger in, to separate "long sleep" from "on battery", then without
`hp_omnibook_5_ec`.

The owner's note: the fan and the LED cannot be judged with the lid shut;
the script should read the EC's fan speed itself rather than ask.

## B. A/V test device tree

Booted from "Ubuntu on SSD: A/V test device tree", without
`clk_ignore_unused`, `pd_ignore_unused` or `arm64.nopauth`.

- **Basics:** keyboard, touchpad, Wi-Fi (HTTP 204 from the connectivity
  check), the speakers (heard), the brightness keys, the EC hotkeys and the
  power key all work. `UBSAN|Oops|WARNING:|context fault|blocked for`:
  nothing.
- **GPU** (`mesa-test-20261122T120044.txt`): glmark2 13765, `vkcube` 1000
  frames, `gnome-shell` on the GPU.
- **Camera:** the UVC camera is `/dev/video0` on this tree (Iris takes
  `video2`/`video3`). It works: frames are pure black (Y average 16) with
  the privacy shutter closed and normal (Y average 110–135) from the first
  frame with it open.
- **Shutter sensor: none that Linux can see.** Both UVC functions (RGB
  `video0`, IR `video4`) offer the read-only `privacy` control, but it
  reads 0 with the shutter closed and open. No input device has a
  camera-cover switch, and the only camera device in HP's DSDT is
  Qualcomm's MIPI `CAMS` (`QCOM0F26`), which `_STA` disables. The shutter
  is mechanical as far as Linux is concerned; whether Windows shows a
  shutter state is not checked.
- **Camera app:** GNOME Snapshot found no camera. PipeWire had no video
  nodes: `52-no-v4l2-monitor.conf` turns WirePlumber's V4L2 monitor off
  on purpose for the Iris trees, and the libcamera monitor, which started
  at login, added no camera. A restart of WirePlumber alone (12:07) made
  libcamera add both cameras (`uvcvideo` pipeline handler) and PipeWire
  offer them as `Video/Source`. The likely cause is that libcamera looked
  before the session's device ACLs were applied; not confirmed. The same
  restart found both cameras on the test-tree boot.
- **Iris, plain test** (`video-test-20261122T114039.txt`): with Qualcomm's
  Mahua data and no diagnostic parameters, the firmware boots
  (`video-firmware.3.6-aeb98f00...`), and the decoder (H.264, HEVC, VP9,
  AV1) and encoder (H.264, HEVC) register. Every H.264 decode ends in
  `session error received 0x4000003: fatal error`, then `0x4000004:
  invalid operation for current state`.
- **Iris, `--mahua`** (`video-test-20261122T114238.txt`,
  `journal-kernel-iris-smmu-deadlock.txt`): trials 1–3 behaved as on
  `-20` (the firmware boots, ffmpeg is killed after 30 s, `failed to
  suspend` every 1.5 s). Trial 4 (`diag_hw_core=-1`, no hardware-core
  bits) did not boot the firmware: two `arm-smmu 15000000.iommu:
  Unhandled context fault` (SIDs `0x19e2` and `0x19e0`), `error booting up
  iris firmware`, then `TLB sync timed out -- SMMU may be deadlocked` 445
  times until the reboot. The display dropped frames (`crtc112 event 1
  overflow`), and after 2 minutes the GPU's job worker was blocked on a
  mutex held by `v4l_id`, which was stuck opening the Iris device. The
  desktop crawled until a forced reboot 8 minutes later. On `-20` the
  same trial booted the firmware. `check-video.sh` no longer runs that
  trial, and stops the trials at the first boot failure or SMMU fault.
- **External display:** not run.

## Next

- **Kernel:** `CONFIG_QCOM_SPMI_ADC5_GEN3=m` (the PMH0110 temperature
  alarm); restore `qcom,usb3-lane-a-overrides` in the test tree.
- **Suspend:** the 10-minute cycle on AC, then without the EC driver. The
  sleep depth now works, so the drain figure will mean something once the
  battery freeze is understood.
- **Headset:** the swap is before SoundWire (codec DMA channel mapping or
  the RX macro); the alert storm points at the headset bus's read path.
- **Iris:** the firmware's fatal session error on H.264 with Qualcomm's
  Mahua data; no more `--mahua` trials on this base.
- **Clock:** the ABD time request.
- **C**, the daily entry: the power key, the Dell receiver directly in
  each USB-C port, F6/F9 and audio.
