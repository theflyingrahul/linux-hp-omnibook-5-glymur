# Kernel -23 results, November 21, 2026

The first boot of `7.3.0-glymur-23` was on the test device tree (model
`(test)`), the morning of November 21, after `install-from-usb.sh` on `-21`.
The tests follow `docs/linux-runbook-23-2026-11-11.md`, section A. The boot
stick was in the USB-A port from power-on, because it is the boot loader.
Raw logs are in `captures/2026-11-21-k23/`. The RTC still does not work, so
the boot report carries the pre-NTP time in its name
(`boot-20261002T230652-4f88b1a5.txt`).

| Step | Result |
| --- | --- |
| A1 boot report and logs | pass |
| A2 UEFI delete | pass |
| A3 headset | First run invalid (script bug, fixed). Reruns: **first sound from the headset**, and its microphone records on `SWR_MIC0`. Left and right change from one playback to the next. Jack detection and the button still do not work. |
| A4 USB-A stress | Rerun with the fixed test: SuperSpeed 20 of 20, no real link errors |
| A5 USB-C | Pass: the stick at SuperSpeed in both ports, a full-speed receiver in both, a USB 2.0 hub in both, runtime resume clean. One `-62` enumeration failure at SuperSpeed, which recovered. The receiver on USB-A was reset repeatedly. |
| A6 charging | pass, as on earlier kernels |
| A8 timeout OSD (hold F5) | pass (owner) |
| C daily entry | pass: audio, F6 and F9, the USB-C stick at SuperSpeed, USB-A stress 20 of 20 with Linux's values |
| A7 suspend, B | not run yet |

## A1. Boot report and kernel log

- The USB-A section shows HP's overrides `00000158 000000a0 00000178
  00000090`. The PHY driver logs both lane-A writes and reads them back:
  `0x158 = 0xa0`, `0x178 = 0x90`.
- The stick enumerated at 5000 Mb/s on bus 3, with `errors: 0` on both
  USB-A buses.
- `failed to set target rate`: 0. `/sys/class/nvme/nvme0/speed` is absent,
  as `-22` intends.
- No `UBSAN`, `Unbalanced` or `completion timeout` lines.

## A2. UEFI variable

`check-efivars-write.sh --delete` printed `deleted`. The variable count went
from 99 to 98. Writing only the attribute header works as a delete through
Qualcomm's variable service (`efivar-write-20261121T084743.txt`).

## A3. Headset: the test did not run

Every `amixer cset` and `cget` by name failed with `Cannot find the given
element from control sysdefault:0`, 38 times. So the routing never changed:
- The tones went to the speakers, as the owner heard: "speakers", then
  "speaker right".
- The 12-input microphone scan recorded whatever was already routed. Its
  near-full-scale peaks on every input mean nothing.
- The jack readings came from controls looked up by number, which were
  shifted. They are not reliable either.

The cause is alsa-lib's control layer, not the kernel:
- `amixer -c 0` opens `sysdefault:0`. For this card, that goes through
  UCM's `ctl.remap` plugin, which alsa-ucm-conf's `lib/ctl-remap.conf` and
  `codecs/wsa884x/two-speakers/init.conf` save at boot to
  `/var/lib/alsa/card0.conf.d/ctl-remap.conf`.
- The remap adds a virtual stereo `Speakers Volume` as numid 1 and shifts
  every other numid by one. For example, amixer lists numid 155 as `RX_MACRO
  RX0 MUX`, while the kernel's 155 is `RX_MACRO RX1 MUX`.
- Through the remap, 243 of the card's 244 controls fail a lookup by name.
  Only `Speakers Volume` is found.
- The kernel's own lookup is fine. `SNDRV_CTL_IOCTL_ELEM_INFO` by name
  returns `RX_MACRO RX0 MUX` at numid 154 and `DEC0 MODE` at 95, and
  `amixer -D hw:0` finds every control.

On `-20` and `-21` the same script set these controls by name, and those
logs list 243 controls with no `Speakers Volume`. The alsa-lib (1.2.16.1),
alsa-ucm-conf and HP UCM files have not changed since before `-20`. Why the
remap applies now and did not then is not known.

**Fix:** `check-headset.sh` and `check-audio.sh` now use `amixer -D
hw:$CARD`, which skips the remap. Playback and capture already used
`plughw`.

### A3 rerun (09:07, `headset-test-20261121T090740.txt`)

Two runs stopped early (`090655`: the left tone was heard as "nothing", then
stopped; `090734`). The third ran to the end. Every route control now
reads back as set (RX path: `RX_CODEC_DMA_RX_0` on, `RX0`/`RX1` muxes on
`AIF1_PB`, `CLSH_DSM_OUT`, `FU 6 Channel Switch` on,on).

- **Playback works.** This is the first time the headset jack played
  anything; on `-21` the tones were "stuck". The owner heard the `left`
  tone (channel 0 only) in the **headset right** and the `right` tone in
  the **headset left**.
- **The microphone records.** `SWR_MIC0` recorded 2 s with a changing
  envelope on channel 0 only (rms about 7460, peak 32768, 1435 clipped
  samples at `TX_DEC0 Volume` 110, which is +26 dB). Played back, the owner
  heard it "only on the left side, noisy". On `-21` the headset
  microphone read peak 0.
- **Left and right are not settled.** The tone and the recording are both
  channel 0 and went through the same route, yet one was heard on the
  right and the other on the left. One of the two answers is probably
  wrong. A quick recheck with the headset worn the right way round settles
  it before the channel map is changed anywhere.
- **The other eleven inputs** (`SWR_MIC1` to `11`) give `arecord: read
  error: Input/output error` and no samples. The kernel logs nothing for
  them. Most likely nothing is wired behind them on this board; the scan
  has found its input.
- **The volume step did not run.** The script took the range from the TLV
  line as well (`min=0 -128`), and bash failed on it. The control is Q7.8
  dB, linear: the value minus 32768, in 1/256 dB (`sdca_asoc.c`,
  `q78_write`). So 25088 is -30 dB, and the old "half of the range" would
  have been about 0 dB. The script now parses the `type` line and steps to
  -40 dB, then -20 dB (22528, then 27648).
- **Jack detection still does not work.** `GE 35 Detected Mode` stays 0
  and `Headphone Jack` reads `on` whether the headset is in or out.
  `Mic Jack` stays `off`. Pressing play/pause produced no input event.
  The kernel logged one `ASoC error (-16)` reading register `0x40c00908` on
  `snd_soc_sdca.SimpleJack.0` (09:08:49), and at boot `supply vdd-mic-bias
  not found, using dummy regulator`.
- `TX_DEC0 Volume` in the microphone scan is now 96 (+12 dB), so the
  recording does not clip.

### A3 recheck (09:17, `headset-test-20261121T091659.txt`)

- **Left and right change from one playback to the next.** The `left` and
  `right` tones were heard on the correct sides. But the first tone of the
  volume step, the same `left.wav` at -40 dB, played on the **right**
  ("the first one played on the right side"). In the 09:07 run both tones
  were swapped. Every `aplay` opens a new stream through the same route, so
  the swap comes and goes per stream. It is not the wiring or a fixed
  channel map. It looks like the two channels starting one slot out of step
  on some stream starts: in the codec DMA, the RX macro or the SoundWire
  port. The voice playbacks are consistent with this: the recording is
  channel 0 only, and both times it was heard on the left.
- **Volume step:** it set 22528 (-40 dB), then 27648 (-20 dB), and both
  read back. The owner could not judge whether the second was louder,
  because the first played on the other side. Repeat with the tones on one
  side.
- **Microphone:** `SWR_MIC0` again, now at +12 dB: peak 32768 with only 54
  clipped samples (1435 at +26 dB), rms 3268. Heard back "faint with some
  background white noise", on the left only, as a mono recording should.
  The other eleven inputs again gave `Input/output error`.
- **Jack and button:** unchanged. The detected mode is 0 and `Headphone
  Jack` is `on` with the headset in or out. Play/pause gave no event. The
  same `SimpleJack` `ASoC error (-16)` on register `0x40c00908` appeared
  during the button capture (09:18:33), as at 09:08:49, so the read fails
  each time.

## A8. Keyboard backlight timeout OSD

Holding F5 still shows the timeout on `-23` (owner: pass).

## A4. USB-A SuperSpeed stress (HP's values)

The summary line was `back at SuperSpeed 10, at high speed 10, gone 0 of 20;
link errors in all: 1`. That reading is misleading.
- **Odd cycles** (a USB device reset) all ended at SuperSpeed. Cycle 1 reset
  the stick on its SuperSpeed link. Every later odd cycle found it on the
  high-speed port. The reset made it try SuperSpeed again and re-enumerate
  there, so the ioctl returned `ENODEV` (logged as "failed"). That makes 10
  SuperSpeed trainings out of 10, nine of them from scratch.
- **Even cycles** (SuperSpeed port power off, then on) all ended at high
  speed, by design. With its SuperSpeed link down, a USB 3 device connects
  on the USB 2 port and stays there until a USB 2 reset. The script did not
  reset it, so these cycles never asked for SuperSpeed.
- The one link error was on cycle 1. The 1 GiB read before the cycles ran
  at 89 MB/s with 0 errors.

**Fix:** `check-usb.sh --ss-stress` now resets the stick on the high-speed
port after each power cycle, so every cycle should end at SuperSpeed, and a
high-speed or missing result is a real failure. It reports `ENODEV` as "ok,
re-enumerated".

### A4 rerun (09:10, `usb-test-20261121T090951.txt`)

- `back at SuperSpeed 20, at high speed 0, gone 0 of 20`, every cycle at
  5000 Mb/s. Each power-cycle-and-reset took the stick from high speed back
  to SuperSpeed.
- The 1 GiB read ran at 105 MB/s.
- The total of 10 "link errors" was again the test's own doing: each odd
  cycle's reset logs `reset SuperSpeed USB device`, which the error pattern
  counts. So the first run's single error (cycle 1) was also its own reset,
  and neither run had a real link error. The script now subtracts its own
  SuperSpeed resets.
- Afterwards the automount rule was gone, and the stick stayed at 5000 Mb/s,
  unmounted.

This is HP's values on the test tree. Boot C, the same test on the daily
tree with Linux's values, is the comparison.

**Automount.** GNOME mounted the stick's FAT and NTFS partitions again on
every re-enumeration, then lost them mounted on the next cycle. The script
now sets `UDISKS_AUTO=0` for that stick while it runs, through a rule in
`/run/udev/rules.d/`. The `Volume was not properly unmounted` warning for
`sda1` and `sda2` was already there at this boot's first mount, before the
test. A read-only `fsck.vfat -n` of both is due before the next write to the
stick. After the run, the stick stayed on the high-speed port (cycle 20 was
a power cycle) until the next replug or reboot.

## A5. USB-C (partly done)

`usb-test-20261121T085802.txt`:
- A Dell Universal Receiver (full speed, 12 Mb/s) plugged straight into
  connector 0 (`a600000.usb`, `usb_0`) enumerated on the first attempt, with
  no `error -71`. Full and low speed on `usb_0` failed in every earlier
  record. This is the first mouse test since `-20` added the PHY's SE0
  timeout and the repeaters' 3 V rail, so it cannot be credited to `0087`
  alone.
- An iPhone enumerated at high speed on `usb_0` earlier in the boot.
- Both eUSB2 repeaters identify (`parent PMIC subtype 0x5f v2.0`).
- No kernel warnings.
- `usb-test-20261121T091208.txt`: the receiver in connector 1
  (`a800000.usb`, `usb_1`) also enumerated at full speed on the first
  attempt, with no `-71` and no kernel warnings. That is one plug on each
  port.
### A5, the rest (09:23 to 09:26)

The owner moved the boot stick (SanDisk Ultra, 57.3 GB, through an
adapter) to the USB-C ports and put the Dell receiver in the USB-A port.
The five `usb-test-20261121T0923…0926` logs and
`journal-kernel-usb-c-0920-0927.txt` cover these steps.

| Log | Connector 0 (`a600000`) | Connector 1 (`a800000`) | USB-A (`a000000`) |
| --- | --- | --- | --- |
| `092354` | stick, 5000M | charger (PD) | receiver, 12M |
| `092447` | charger (PD) | stick, 5000M | receiver, 12M |
| `092516` | USB 2.0 hub: a 119 GB card or disk at 480M, the receiver at 12M | (stick re-enumerating) | empty |
| `092540` | hub, as above | stick, 5000M | empty |
| `092613` | stick, 5000M | hub, as above | empty |

- **SuperSpeed on USB-C:** the stick came up at 5000 Mb/s on both ports.
  One enumeration on connector 1 failed with `device not accepting address
  4, error -62` (09:25:08). The next one, at 09:25:34, came up at
  SuperSpeed.
- **Full speed:** the receiver worked on USB-A, behind the hub on both
  USB-C ports, and (earlier) directly on both USB-C ports.
- **The hub:** a USB 2.0 hub with its own PD supply (the port is a PD
  source partner) enumerated on both ports, with a card or disk and the
  receiver behind it.
- **Runtime resume (`0087`):** afterwards every root hub's `power/control`
  reads `on`, which only the loop sets, and the kernel logged no
  `port_wait_reset`, USB reset or `-16`. Both disks were still listed. Pass.
- **The receiver on USB-A was reset repeatedly.** Between 09:24:30 and
  09:25:05, the kernel reset it six times. One reset reported `device firmware
  changed` and re-enumerated it. Then came `Timeout while waiting for setup
  device command` and `device descriptor read/all, error -110`, just
  before it was unplugged at 09:25:05. Two of the resets fall within
  half a second of a USB-C unplug or role change (09:24:30, 09:24:57). So
  either USB-C plugging disturbs the USB-A port's full-speed link, or the
  plugging moved the laptop. Before this, USB-A had only been tested with
  high- and SuperSpeed devices. To repeat: the receiver alone in USB-A for
  a few minutes, then a USB-C plug while it is in use.
- The 119 GB NTFS volume behind the hub mounted with `volume is dirty` (its
  own state, not this test's).

### USB-A repeat (09:30, `journal-kernel-usb-a-repeat-0927-0931.txt`)

The receiver alone in the USB-A port from 09:30:06. The owner used the
mouse, then unplugged and replugged the boot stick in USB-C connector 0
three times (09:30:18 to 09:30:55). The mouse never froze, and the kernel
logged no reset or error on bus 2. So the earlier resets did not reproduce
when USB-C was plugged on purpose. More likely, handling moved the
receiver.

Two side findings:
- The third replug of the stick came up at **high speed** (480M, bus 4);
  the first two came up at SuperSpeed. Both ports read `orientation=reverse`
  then. Earlier logs show both orientations (18 `normal`, 46 `reverse`), so
  detection works. A slow or angled insertion is the likely cause; it is one
  of three plugs.
- At 09:29:13, something on connector 1 (`con2`) brought 29 lines of `ucsi_glink:
  con2: Firmware bug: duplicate partner altmode SVID 0xff01`: the
  firmware listed the partner's DisplayPort mode 29 times. Earlier, an
  iPhone behind the hub attached as `ipheth`, got `urb status: -71` and
  disconnected 2 s later.

### USB-A full speed fails on its own (09:31, `journal-kernel-usb-a-fs-resets-0931.txt`)

This corrects the reading above. From 09:31:15, with no USB-C activity, the
receiver in the USB-A port was reset every 2 to 4 s, 28 times by 09:32:55.
There were `Device not responding to setup address` failures and two `device
firmware changed` re-enumerations. It was still going at the end of the
capture. The device was never runtime-suspended (`power/control` `on`,
`runtime_suspended_time` 0), so this is the link, not autosuspend. Each time
it worked for about a minute after enumerating (09:23:39 to 09:24:30,
09:30:06 to 09:31:15), then started failing.

Unlike the two USB-C PHYs, the USB-A port's eUSB2 PHY (`phy@88e0000`) has
no repeater in the device tree. On USB-C, full and low speed failed until
the repeaters were declared (`-8`) and configured (`-20`). The USB-A port's
repeater is not identified. HP's power votes suggest it has one
(`docs/eusb2-repeater-2026-09-30.md`). There is no PMIC at SMB2370 SID 11:
the September `-8` probe of `pmic@b` failed with `-5`. So it is a different
part, or on a different bus. Finding it needs the ACPI and Windows
evidence. High speed and SuperSpeed on this port are not affected.

The stick's replug into USB-C connector 0 at 09:32:32 came up at **high
speed again**, with `orientation=reverse`: two high-speed results in a row,
after two at SuperSpeed.

### The stick flipped (09:33 to 09:35, `journal-kernel-usb-c-flip-0933.txt`)

The owner flipped the stick's USB-C plug and plugged it in several times.
The receiver was still in USB-A until 09:34:23.
- **The stick:** SuperSpeed at 09:33:38, high speed at 09:33:52, then
  SuperSpeed on all three plugs into connector 0 (`a600000`) at 09:34:35,
  09:34:46 and 09:34:57. It ended at 5000M with `orientation=normal`.
  Across the session, connector 0 gave high speed on 3 of about 9 plugs.
  Both orientations have given both results (`reverse`: SuperSpeed twice,
  high speed twice). So it is not the orientation switch. SuperSpeed
  sometimes fails to train after a plug on USB-C, as on USB-A. The stick
  sits in an adapter, which adds one more contact.
- **The receiver on USB-A** went on resetting until it was unplugged. Its
  last enumeration read a corrupted configuration descriptor (`config
  index 0 descriptor too short (expected 84, got 32)`, `config 1 has 1
  interface, different from the descriptor's value: 3`): bad data on the
  full-speed link, which fits the missing repeater.

## A6. Charging

`charging-watch-20261121T085408.txt`: two unplug and replug cycles on
connector 0. Each replug came up as Type-C 3.0 A, then a PD contract
(3.25 A) about 0.5 s later, and the status returned to `Charging`. No
command failed. `ac` and `usb` stay `0`, as known.

`check-battmgr-notify.sh` (60 s): `qcom_battmgr_state_callback` 0 calls,
`qcom_battmgr_callback` 7394, in bursts of up to 1473 a second, with the
17-a-second beat between them. This is the `-16` pattern with larger
bursts. There was no hang.

## C. The daily entry (09:37 to 09:50)

`boot-20261002T230650-bf202c9a.txt`: model `HP OmniBook 5 Laptop 16-bf1xxx`
(no `(test)`), `HP PHYC overrides in the device tree: none`, the boot stick
at 5000 Mb/s with `errors: 0`, and no `failed to set target rate`.

- **Audio** (`audio-test-20261121T094904.txt`):
    - the microphone array records on both channels (rms 1571 and 657);
    - the left and right speaker tones played on the correct sides;
    - muting from the desktop lights F6 for the speakers and F9 for the
      microphones;
    - the muted recording is silent (peak 0).

  The script's named mixer reads work through `hw:` here too.
- **USB-C stick:** SuperSpeed on connector 0 (`a600000`, 09:50:07) and on
  connector 1 (`a800000`, 09:50:18).
- **USB-A stress with Linux's values** (`usb-test-20261121T094655.txt`): the
  1 GiB read ran at 81 MB/s. `back at SuperSpeed 20, at high speed 0, gone
  0 of 20; link errors in all: 0`.

**HP's values against Linux's:** both trees retrained SuperSpeed 20 times
out of 20, with no real link errors (A4 rerun: 105 MB/s; daily: 81 MB/s,
one read each). So the stress test does not tell the two apart. The
failures it was built for came at power-on, on 2 of 13 boots. So the
comparison falls to the boot report's USB-A section, boot by boot, on each
tree.

## The clock (boot C, for the Windows-side work)

Each boot starts at the same fake time, `Fri 2026-10-02 23:05:38 IST`
(`journalctl --list-boots`), because nothing sets the clock before NTP.
- `rtc0` is `rtc_qcom_glink`. Every read fails (`0x68 failed (-110),
  falling back`, `all time sources failed`, `hctosys: unable to read the
  hardware clock`), as on `-20` and `-21` (`rtc-test-20261110T172807.txt`:
  `0x68` times out, `0x67` gets no reply, `0x65` acks with `0xffffffff`).
- `RTCInfo` is not among the UEFI variables under Qualcomm's GUID
  `882f8c2b-9646-435f-8de5-f208ff80c1bd` (`rtc-state-boot-c.txt` lists the
  13 that are there). So the upstream PMK8850 path (`qcom,uefi-rtc-info`,
  as on the Glymur Zenbook A16 and QCB) has no offset to read, and the test
  tree keeps `pmk8850_rtc` disabled.
- **The new problem:** Ubuntu 26.04's chrony uses NTS. With the clock at
  October 2, its TLS handshakes fail (`The certificate chain uses not yet
  valid certificate`) and it logs `Can't synchronise: no selectable
  sources` (`journal-chrony-boot-c.txt`). So the time stays wrong for
  minutes after every boot, and anything else that checks certificates
  fails until then.
- Next, on the Windows side: how Windows gets and keeps the time on this
  machine. That means `\_SB.PRTC` (`ACPI000E`) and its `_GRT`/`_SRT`
  through `\_SB.ABD` offset `0x30200`, which service and opcodes that
  reaches, and where the offset is kept.

## Next

1. Headset, for the next kernel:
    - the left/right swap that comes and goes from one stream to the next
      (a channel-slot alignment at stream start; find which block);
    - jack detection: the `SimpleJack` read of `0x40c00908` fails with
      `-16` every time, and the `vdd-mic-bias` supply is missing.
2. A4 with a second USB 3 device, if there is one.
3. The rest of A5, then A7 (suspend from a text console, the 10-minute drain
   cycle on battery) and A8 (hold F5).
4. Boot C (daily entry), `--ss-stress` with the same stick, for the
   comparison with HP's values.
