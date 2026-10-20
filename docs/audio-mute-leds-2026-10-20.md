# Audio: the -14 Crash, Device Names, Mute Switches and LEDs, October 20, 2026

Follow-up to the kernel `-14` test (`docs/audio-headset-path-2026-10-17.md`):
what the crash was, how the built-in audio is named, and how the mute
keys and their LEDs connect to PipeWire. Kernel `-15` and the updated audio
files carry the changes; nothing here has run on the laptop yet.

## The -14 test, read again

- **The crash came after the unbind, not on rebind.** The test log stops at
  "after unbind:" and the Oops fired in the 3 s wait that followed. The
  `bind` write then blocked on the lock the crashed worker held.
- **`gpio12 : out 0` is not a level.** The LPASS LPI pinctrl debug output
  prints the direction and the function number (`0` = GPIO), never the
  pin value. The reset line evidence is the unbind itself: with dummy
  supplies, only the shared reset (LPASS TLMM 12) can take both amplifiers
  off the bus, and both went `UNATTACHED`.
- **USB-A:** the SuperSpeed retry loop ran from the start of the boot (the
  pre-NTP clock, `Jul 28 02:14`) to 21:27:28, about 13 minutes; the 141
  lines saved from 21:24:35 are the end of it.

## The crash: runtime PM left enabled after unbind

`wsa884x_probe()` enables runtime PM with a 3 s autosuspend and nothing
disables it. After an unbind the autosuspend still fires, and
`wsa884x_runtime_suspend()` looks up the regmap with `dev_get_regmap()`,
which returns NULL once devres has released it, so `regcache_cache_only()`
dereferences NULL (`x0 = 0`, fault at offset 0x20). Mainline and
linux-next (2026-10-20) have the same code; `wsa883x.c` has the same
pattern.

`patches/kernel/upstream/qcom-next/0007` replaces `pm_runtime_enable()`
with `devm_pm_runtime_enable()`, the usual fix for this pattern (208 users
in the tree), which disables runtime PM and cancels the pending
autosuspend before the regmap is released. It is in kernel `-15`. `check-audio.sh` no longer unbinds the driver; the reset line
is established.

## Names

Windows calls the built-in audio "Speakers" and "Microphone Array" on
"Qualcomm(R) Aqstic(TM) ACX Static Endpoints Audio Device". On Linux:

- the UCM devices are named "Internal Speakers" and "Microphone Array"
  (their `Comment`, which PipeWire uses as the port name);
- a WirePlumber rule (`boards/hp-omnibook-5-16-bf1xxx/audio/wireplumber/`,
  installed to `/etc/wireplumber/wireplumber.conf.d/`) names the card after
  Qualcomm's Windows driver and the two nodes "Internal Speakers" and
  "Microphone Array". It matches the card by its ALSA name and the nodes by
  their UCM PCM (`hw:MAHUAHPOmniBook,0` and `,1`), so no other card is
  renamed.

## Mute switches and LEDs

The Linux chain for mute LEDs is ALSA's `snd_ctl_led`: a mixer switch
attached to the "speaker" or "mic" LED drives the `audio-mute` or
`audio-micmute` LED trigger. alsa-ucm-conf does this for the Lenovo
ThinkPad T14s (`Qualcomm/x1e80100/LENOVO-T14s.conf`): it creates a user
control `Mic LED Capture Switch` with `cset-new`, attaches it with the
`SetLED` macro from `common/ctl/led.conf`, and names it as the microphone's
mixer element, so PipeWire's mute toggles it. Ubuntu 26.04's alsa-ucm-conf
ships the same `led.conf`.

- The HP profile now does the same for the microphones. For the speakers it
  creates a `Speakers Switch` that joins the existing `Speakers Volume`
  remap in the `Speakers` element. This part has no upstream example: the
  T14s EC driver has a speaker-mute LED too, but its UCM profile leaves it
  unattached. The speaker path has no usable real switch (the WSA macro's
  `Digital Mute` controls are inverted, and the amplifiers' `DAC Switch`
  controls are SoundWire port enables, not mutes), so the same
  created-switch mechanism is the only way to light that LED. Neither switch acts on the hardware.
  The audio is still muted: when a device's mute changes, PipeWire sets
  the node's `softMute` along with `mute` (`alsa-acp-device.c`), so the
  samples are muted in software too.
- The HP EC driver gives its LEDs the default triggers `audio-mute`
  (`platform::mute`, F6) and `audio-micmute` (`platform::micmute`, F9), as
  `thinkpad_acpi` and others do. The triggers are registered by
  `snd_ctl_led`, which the UCM macro loads.
- The LEDs follow Linux's mute state from boot on. The earlier wish to
  carry the mute state over from Windows (the EC keeps the LEDs across
  reboots, `docs/ec-2026-09-30.md`) is not covered: the trigger sets the
  LEDs to the Linux state as soon as it attaches.

## The keys

- **F6** sends the HID Consumer "Mute" usage, which GNOME turns into a
  speaker mute. With the switch above, the F6 LED follows it.
- **F9** sends the same HID usage (`docs/keyboard-hotkeys-2026-09-29.md`),
  so today it mutes the speakers too. HP's ACPI reports F9 as EC event
  `0x11` (WMI code `0x270`), which the EC driver maps to `KEY_MICMUTE`, but
  no EC event has ever arrived (issue #11). The ACPI generic buttons device
  (`BTNS`, `ACPI0011`) has only the power button and volume usages, so
  Windows' mic mute comes from the EC.
- HP's ACPI has a `_DSM` on the EC's event device (`ECGE`) that queries
  the EC's "who am I" (command `0x43`) and capabilities (`0x44`, six bytes
  with an interface version), Qualcomm's reference EC handshake. Linux
  has never sent either. Whether Windows calls it, and whether the EC
  needs it before raising events, is not known, so it stays out of the
  kernel: `docs/linux-runbook-2026-10-20.md` tests it from userspace with
  read-only `i2cget`/`i2ctransfer` and watches the line with `gpiomon`,
  and also captures the keyboard's raw HID reports for F6 and F9.
  `check-audio.sh` counts EC interrupts across an F9 press.

## Is this the standard way?

| Change | Upstream precedent |
|---|---|
| `wsa884x`: `devm_pm_runtime_enable()` | The common fix for a driver that never disables runtime PM |
| EC LEDs' `audio-mute`/`audio-micmute` default triggers | `lenovo-thinkpad-t14s.c` (the arm64 ThinkPad EC), `dell-laptop`, `asus-wmi`, `hid-lenovo` |
| Mic LED: `CtlNew` + `SetLED` + `CaptureMixerElem` | alsa-ucm-conf: ThinkPad T14s, AMD `acp-dmic`, HDA |
| Speaker LED: the same with a created `Speakers Switch` | None (see above) |
| Device names: UCM `Comment` and a WirePlumber `monitor.alsa.rules` rule | WirePlumber's documented way to rename devices and nodes; upstream UCM profiles use generic names ("Speaker playback") |
| Topology, UCM structure | Byte-identical to upstream's Zenbook A14 topology; UCM follows the A14 profile |

Nothing here adds a new mechanism. For upstream submission the names
would go back to alsa-ucm-conf's generic ones; the Windows names are a
local choice of the owner.

## Capture format

The Zenbook A16 profile in alsa-ucm-conf notes that its DMICs "return a
square-ish wave at S16_LE" and uses S32_LE. This laptop's `-13` recording
at S16_LE is ordinary audio (about 11,000 distinct sample values per
channel, 0.1 % of samples at full scale from tapping), so the HP profile
keeps S16_LE, which matches its topology.

## Upstream, 2026-10-20

- qcom-next: still `1a0586064ee1`; the newest tag is
  `qcom-next-7.3-rc4-20261014`.
- Mainline `v7.3-341-gf47d223627`: the only commit in our drivers is
  `8cb5c17be3` "i2c: qcom-geni: Restore the source-clock selection
  policy", which fixes `cb97bf3d4f`. qcom-next never took `cb97bf3d4f` and
  already uses the restored policy, so neither applies.
- alsa-ucm-conf: unchanged since 2026-08-31. audioreach-topology: one new
  board (Vicharak Axon Pro), no macro changes. The laptops kernel branches
  are unchanged.
