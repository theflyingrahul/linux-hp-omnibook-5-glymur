# Speakers silent on kernel -15, October 21, 2026

The owner reports the internal speakers no longer play (kernel `-15`, test
device tree, boot of 2026-10-21 20:02). Raw output: `captures/2026-10-21-audio/`.

## What the laptop shows

- **Both WSA884x amplifiers are `UNATTACHED`** on `sdw-master-1-0`
  (`sdw:1:0:0217:0204:00:0` and `:1`), runtime PM `active`, driver bound.
  The ASoC card (`MAHUA-HP-OmniBook-5-16-bf1xxx`) and PipeWire's "Internal
  Speakers" sink exist, and the mixer controls are all at their defaults
  (`Speakers` on, `SpkrLeft/Right PA` at 6), so the software stack is
  complete. Nothing is playing: no amplifier is on the bus to take the
  stream.
- **The shared reset is asserted.** `gpiochip3` (the shared-GPIO proxy in
  front of LPASS TLMM 12) shows `reset out hi ACTIVE LOW`, and
  `gpio12 : out 0` in the pin view: the line is held at its asserted level.
- **One bus event this boot:** `qcom-soundwire 6c80000.soundwire:
  qcom_swrm_irq_handler: SWR bus clsh detected` at 20:07:14 (about four
  minutes after boot), twice in the log. No parity errors this time.
  Nothing else from `wsa884x`, `q6apm` or `snd` follows, so the amplifiers
  left the bus without a log line.
- **Boot-time hint:** `qcom-apm gprsvc:service:2:1: CMD timeout for
  [1001021] opcode` at 02:14:08 (pre-NTP clock), just before the card
  binds; `wsa884x` also reports its `vdd-io`/`vdd-1p8` supplies as dummy.

## Comparison with earlier boots

| Boot | SoundWire status |
| --- | --- |
| `-13`, 2026-10-17 | amplifiers attached (reset on TLMM 204/205) |
| `-14`, 2026-10-17 | attached, until the unbind test |
| `-15`, 2026-10-20 | `Alert` in the first check; bus clash at 15:52:26 and parity errors on both amplifiers at 15:52:55–56; the owner still heard left and right tones; `UNATTACHED` in the next check |
| `-15`, 2026-10-21 | `UNATTACHED` after the clash at 20:07:14 |

So the amplifiers attach and play after boot, then a bus clash is followed
by the amplifiers dropping off the bus on both `-15` boots, and they do not
come back. The first `-15` boot was still audible for several minutes after
the clash, so the drop is not immediate. What triggers the clash is not
known: it fits neither a stream start nor a mute in these logs.

## Microphones

Work. 5 s through PipeWire gave a room-noise recording (rms about 830 on both
channels, one full-scale click in the first second from the stream start).
The microphones use the VA macro's digital microphones, which are
independent of the SoundWire amplifiers.

## What was not done

- No unbind or rebind of `wsa884x`: it crashed `-14` and `-15` carries the
  fix, but the runbook still forbids it.
- No GPIO write to the reset line.
- A reboot is expected to bring the amplifiers back (they attached on every
  fresh boot before); that is the owner's call.

## Next

1. After the reboot, run `check-audio.sh` right away, then again after a
   few minutes of use, and note when `UNATTACHED` first appears
   (`cat /sys/bus/soundwire/devices/sdw:1:0:0217:0204:00:*/status`).
2. Compare the CRD, the EliteBook X G2q and the ThinkPad T14s Gen 7 for
   what they do on the WSA bus clock/data pins (`wsa_swr_clk`/`wsa_swr_data`
   pin state, drive strength, bias) and for WSA macro/`swr0` clock-stop
   properties. HP's DT currently relies on the Glymur defaults.
3. Check whether `qcom-soundwire` has clock-stop or a bus-reset path that
   re-enumerates a device that left the bus; if not, that is the upstream
   gap.
