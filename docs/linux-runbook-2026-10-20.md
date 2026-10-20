# Linux-Side Runbook, October 20, 2026

Step-by-step work for the next session on the laptop itself (the Ubuntu
install on the SSD, kernel `-15`, test device tree). Each step says what to
run, what to look for and what each outcome means. The steps only read
the EC, or unbind and rebind its driver; nothing here writes to the EC,
the SSD's other partitions or the firmware. Background:
`docs/audio-mute-leds-2026-10-20.md`, `docs/ec-2026-09-30.md`,
`docs/keyboard-hotkeys-2026-09-29.md`; issues #1, #11 and #28.

## Ground rules

- Check that this is the right system first: `uname -r` should be
  `7.3.0-rc4-glymur-15` and `findmnt -n -o LABEL /` should say
  `glymur-root`; `tr -d '\0' < /sys/firmware/devicetree/base/model` should
  end in "(test)".
- Prefer what upstream already does. Before proposing a kernel, UCM or
  WirePlumber change, find the existing driver, profile or rule that does
  the same thing (the ThinkPad T14s, the Glymur CRD and HP's EliteBook X
  G2q are the nearest relatives) and follow it. Say so when there is none.
- Never write to the EC with raw `i2cset`/`i2ctransfer` writes, never
  write the reference "enable events" command `0x35` (HP's ACPI never
  sends it), and never unbind the audio amplifier driver (`wsa884x`): on
  `-14` that crashed the kernel.
- Reboots are the owner's call. Ask before anything that needs one.
- Keep raw logs under `/var/log/glymur/`. Put sanitized copies in
  `captures/<date>-<topic>/` and findings in a new
  `docs/<topic>-YYYY-MM-DD.md`, then update `docs/status.md`,
  `docs/progress-log.md` and the matching GitHub issue. Commit in the
  repository's style (`docs: ...`, `audio: ...`); push only when the owner
  says so.

## 1. Install kernel -15 and the audio files

If not done yet, from the desktop terminal:

    bash "/media/$USER/UBUNTU 26_0/glymur-tools/kernels/install-from-usb.sh"

It installs the kernel, the AudioReach topology, the UCM profile and the
WirePlumber names. The owner then reboots into "Ubuntu on SSD: test device
tree".

## 2. USB-A first

The boot stick's SuperSpeed lane failed to train for about 13 minutes on
the last boot (`docs/usb-a-bringup-2026-09-29.md`). Right after login:

    lsusb -t
    journalctl -k -b | grep -c 'usb3-port1: Cannot enable'

The stick should sit on the 5000M (or 10000M) bus and the count should be
0. If the loop is back, note the time it started and how long it lasts.
Do not reseat the stick (it is the boot medium).

## 3. Audio

    sudo bash ~/check-audio.sh

Answer its questions; it asks before every sound and every mute. Check:

- **Names.** `wpctl status` should list "Internal Speakers" and
  "Microphone Array", and the `pw-dump` lines should show
  `device.description` "Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio
  Device". If not, the WirePlumber rule
  (`/etc/wireplumber/wireplumber.conf.d/51-hp-omnibook-5-16-audio.conf`)
  did not match: compare its `alsa.card_name` and `api.alsa.path` patterns
  with `pw-dump` and fix the rule, not the UCM profile.
- **LED binding.** `/sys/class/sound/ctl-led/speaker/card*/list` should
  name `Speakers Switch` and `.../mic/card*/list` `Mic LED Capture
  Switch`; the LEDs' triggers should be `[audio-mute]` and
  `[audio-micmute]`.
- **The muted recording must be silent.** The script records 3 s with
  the microphones muted and prints "SILENT, OK" or "NOT SILENT". The mute
  switches are UCM-created controls; PipeWire must still mute the samples
  (it sets `softMute` with `mute`). If it is not silent, the microphone
  is not muted when the desktop says it is: report it at once, and take
  `CaptureMixerElem`/`CaptureSwitch` back out of
  `ucm2/HP/OmniBook-5-16-bf1xxx/HiFi.conf` until it is understood.
- **Speakers.** A tone on the left, then the right. Both silent means look
  at `journalctl -k -b | grep -iE 'wsa|swr|sdw|q6apm|ASoC'` for the first
  error; one side only means compare the two amplifiers' entries in the
  SoundWire list at the top of the log.
- **F6.** The speaker-mute icon in GNOME, and the F6 LED on while muted.
- **F9.** Expected for now: it also mutes the speakers (it sends the same
  HID Mute as F6) and the EC interrupt count does not change. Step 4 is
  about this.

## 4. The F9 key and the EC event line (issue #11)

F9 should mute the microphones. HP's ACPI reports it as EC event `0x11`,
signalled on GPIO 66 (falling edge, pull-up), which the EC driver maps to
`KEY_MICMUTE`. No EC event has ever reached Linux. The steps below find
where it stops, without changing the kernel.

Tools (install once): `sudo apt install gpiod i2c-tools evtest`.

### 4a. The state with the driver bound

    grep -i omnibook /proc/interrupts
    sudo grep -A1 'gpio66' /sys/kernel/debug/gpio
    sudo grep -r 'gpio66' /sys/kernel/debug/pinctrl/*/pinconf-pins /sys/kernel/debug/pinctrl/*/pinmux-pins 2>/dev/null

Then press F9, F11 and F5 a few times each and read `/proc/interrupts`
again. Also run `sudo evtest`, pick "HP OmniBook 5 EC hotkeys", and press
F9: a `KEY_MICMUTE` event means the line works and the problem is solved.

### 4b. Watch the line itself

Unbind only the EC driver, so the GPIO is free:

    echo 9-0076 | sudo tee /sys/bus/i2c/drivers/hp-omnibook-5-ec/unbind
    gpiodetect            # the TLMM is the chip with 251 lines
    sudo gpiomon --chip gpiochipN --bias pull-up --edges both 66

Press F9 several times, then F11, then F5, and stop `gpiomon` with Ctrl+C.

- **Edges appear:** the EC signals, and the driver's interrupt never
  fires. Look at the interrupt setup: the test device tree's
  `interrupts-extended = <&tlmm 66 IRQ_TYPE_EDGE_FALLING>`, the PDC
  mapping of GPIO 66 (`/sys/kernel/debug/irq/irqs/<n>` for the IRQ from
  4a) and how the Glymur CRD and the ThinkPad T14s describe their EC
  interrupt. Read the pending event with `sudo i2cget -y 9 0x76 0x05`
  (read-only) right after a press.
- **No edges:** the EC does not signal. Go to 4c.

### 4c. HP's "who am I" and capabilities queries

HP's ACPI (`ECGE._DSM`, `IC10._DSM`) defines two read-only queries from
Qualcomm's reference EC: "who am I" (`0x43`, one byte) and capabilities
(`0x44`, six bytes, the last one an interface version). With the driver
still unbound:

    sudo i2cget -y 9 0x76 0x43
    sudo i2ctransfer -y 9 w1@0x76 0x44 r6

Record both answers. Then repeat the `gpiomon` run from 4b. Edges now,
none before, means the EC waits for this handshake: the fix is then to send
the same two reads in the EC driver's probe (`patches/kernel/upstream/
qcom-next/0005`), with this result as the evidence. No edges either way
means the handshake is not it; stop here and report.

Rebind afterwards:

    echo 9-0076 | sudo tee /sys/bus/i2c/drivers/hp-omnibook-5-ec/bind

### 4d. The keyboard's raw reports for F6 and F9

Both keys send the HID Consumer "Mute" usage as input events. The
keyboard (`QTEC0001`, I²C HID at 0x3a) also has vendor-defined report
collections that Linux ignores; HP's software may tell F9 apart there.

    for h in /sys/class/hidraw/hidraw*; do echo "$h $(grep HID_NAME $h/device/uevent)"; done
    sudo timeout 20 cat /dev/hidrawN | od -An -tx1 -w32

Press F6 three times, wait two seconds, then F9 three times. Compare the
reports. If F9's differ from F6's in any byte, the upstream ways to act on
it are a hwdb entry (if the usage differs) or a HID-BPF report fixup
loaded with `udev-hid-bpf` (if only a vendor byte differs), not a new
kernel driver. Record the bytes first; decide afterwards.

## 5. Video decoding (issue #9)

    sudo apt install v4l-utils ffmpeg
    sudo bash ~/check-video.sh

`docs/video-iris-2026-10-20.md` explains the setup. Look for:

- an Iris device in `v4l2-ctl --list-devices` and H.264/HEVC/VP9 in its
  output formats;
- the hardware decode finishing with far less user CPU than the software
  one, and no errors;
- in the kernel log, a firmware load and no `qcom_scm`/PAS authentication
  error. An authentication error means the image is refused for this
  laptop: report it, and do not try linux-firmware's `vpu36_p4_s7.mbn`
  (it is not signed for this machine).

If decoding works, the next step is a browser or video player using it
(Firefox and GStreamer use the V4L2 stateful decoders), not more kernel
work.

## 6. External display (issue #7)

Needs a monitor with USB-C input, or a USB-C to DisplayPort/HDMI adapter.

    sudo bash ~/check-display.sh     # nothing plugged in
    sudo bash ~/check-display.sh     # monitor on the hinge-side port
    sudo bash ~/check-display.sh     # monitor on the other port

`docs/external-display-2026-10-20.md` explains the setup. Look for a
`card*-DP-*` connector turning `connected` with modes, the partner's
alternate mode `ff01` active, and a picture in GNOME's display settings.
Try the plug both ways round. If the test boot came up with no picture at
all, boot the daily entry and report: the DP controllers are the test
tree's only display change. DisplayPort audio is not set up yet.

## 7. Quick checks that need no new code

These work on the daily tree too; do them on the same boot.

- **Camera (issue #8).** `sudo apt install v4l-utils ffmpeg`, then
  `v4l2-ctl --list-devices` (the HP True Vision camera has an RGB and an IR
  node) and, for each node,
  `ffmpeg -f v4l2 -i /dev/videoN -frames:v 1 /tmp/camN.png` (the RGB node
  should give a colour picture; the IR node a grey one, possibly dark: the
  IR emitter may need a UVC extension control, which is a separate
  question). Then open GNOME's Camera app (Snapshot).
- **Touchscreen (issue #10).** `sudo libinput debug-events` while touching
  with one, then two fingers; then try scrolling and zooming in a browser.
  Note any dead area or wrong orientation.
- **Bluetooth audio (issue #23).** Pair headphones in GNOME's Bluetooth
  settings, play something (A2DP), then pick the headset microphone in the
  sound settings and record a few seconds (HFP). `wpctl status` shows the
  Bluetooth sink and source.

## 8. Cluster idle (issue #14), no action needed

From `-15` the boot report (`/var/log/glymur/boot-*.txt`, written 60 s
after boot) lists, under `cpuidle`, the idle states and usage counts of
`power-domain-cpu-cluster0`, `-cluster1` and `power-domain-system`.
Non-zero usage on the cluster states means cluster idle works; also look
at `/sys/kernel/debug/pm_genpd/power-domain-cpu-cluster0/idle_states`
after the laptop has sat idle with the screen off for a few minutes.

## 9. Skin temperature limits (issue #16)

`docs/thermal-skin-2026-10-20.md` explains the setup. Check that the four
zones exist and read the EC thermistors:

    for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type); case $t in ec-*) echo "$t $(cat $z/temp)";; esac; done

Then load the CPUs for a few minutes (`sudo apt install stress-ng`;
`stress-ng --cpu 12 --timeout 300`) and watch the zones and
`/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq` every few
seconds. When a zone passes its passive trip (thermistor 4 at 50 °C,
1 at 65 °C, 3 at 75 °C), the CPU frequencies should drop and recover
once it cools. Note the temperatures reached and the fan speed
(`sensors` or the EC hwmon). If the laptop throttles hard at idle or
shuts down unexpectedly, boot the daily entry and report.

Then record the SoC power limits. Windows' PowerLimits device programs
the same hardware that Linux's `qcom_spel` driver exposes (SPEL, see
`docs/thermal-skin-2026-10-20.md`); read what the firmware left set:

    for z in /sys/class/powercap/*/; do echo "== $z $(cat $z/name 2>/dev/null) enabled=$(cat $z/enabled 2>/dev/null)"; for c in $z/constraint_*_name; do [ -e "$c" ] || continue; n=${c%_name}; echo "  $(cat $c): $(cat ${n}_power_limit_uw 2>/dev/null) uW over $(cat ${n}_time_window_us 2>/dev/null) us (max $(cat ${n}_max_power_uw 2>/dev/null))"; done; done

Read the `energy_uj` counters of the `sys`, `soc`, CPU cluster, GPU and
NSP zones before and after the `stress-ng` run as well: that is the first
SoC power measurement on Linux. Only read; do not write any limit.

## 10. Report

Write the results of 2–9 into `docs/audio-mute-leds-results-YYYY-MM-DD.md`
(or the topic they belong to), with the raw logs in `captures/`. Update
`docs/status.md`, `docs/progress-log.md` and issues #1 (speakers,
microphones, names, LEDs), #7 (external display), #8 (camera), #9
(video), #10 (touchscreen), #11 (F9, EC events), #14 (cluster idle), #16
(skin temperature) and #23 (Bluetooth audio).
