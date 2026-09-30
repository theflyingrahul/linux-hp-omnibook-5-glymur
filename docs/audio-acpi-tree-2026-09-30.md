# Audio: HP's ACPI Device Tree and Its GPIOs, September 30, 2026

Continuing from `docs/audio-evidence-2026-09-29.md`, which left two open
questions: whether HP's DSDT and the ADSP driver-pack's `adsp*.jsn` files
would reveal the internal speaker/microphone wiring. Read-only work
against the DSDT already captured privately in `.work/`; nothing tested
on Linux.

## The `adsp*.jsn` lead didn't pan out

`adspr.jsn`, `adsps.jsn` and `adspua.jsn`
(`boards/hp-omnibook-5-16-bf1xxx/firmware/qcsubsys_ext_adsp8480_4500R_HDCP_WHQL/`)
are all the same tiny shape: service-restart (`servreg`) domain
configuration for the ADSP's three protection domains (`root_pd`,
`sensor_pd`, `audio_pd`) — an ACK-timeout knob, nothing else. No
topology, routing, or endpoint data. This specific evidence lead is
closed.

## HP's ACPI audio tree

```
\_SB.ADSP.ADCM                    HID: none of its own; CHLD lists
                                   QCOM0FF6, QCOM0FB7, QCOM0FF4
    .ASCD                        SoundWire host/codec parent
        .QSJ0.SJ01                the one SDCA headset-jack codec
                                   (already covered: blocked upstream,
                                   docs/audio-evidence-2026-09-29.md)
    .AUCD                        HID AUCD\QCOM0FCD ("Aqstic ACX
                                   Audio Device" — Windows' general
                                   audio device)
        .ACXS                     child endpoint(s)
```

This matches the Windows PnP table exactly (`ADCM\VEN_QCOM&DEV_0FB7`,
`AUCD\VEN_QCOM&DEV_0FCD`, etc. from the prior doc) — same devices, now
with their ACPI resource templates.

## Real GPIOs exist, but don't resolve to a usable wiring diagram

Decoded `_CRS` (with a Python script, not by hand — raw ACPI resource
buffers are exactly the kind of thing worth getting a parser to check
rather than counting bytes) and cross-checked against `GIO0`'s own PDC
table with the project's existing `analyze-acpi-pdc.py`:

| Device | Resource | Value | Resolves to |
|---|---|---|---|
| `ASCD` | GpioIo | pin 191 | native GPIO 191 (direct, pin < 250) |
| `ASCD` | GpioIo | pin 2 | native GPIO 2 (direct) |
| `ASCD` | GpioInt | pin 640 | **native GPIO 193** (PDC index 10, IRQ 842, via `analyze-acpi-pdc.py --pin 640`) |
| `AUCD` | GpioIo | pin 204 | native GPIO 204 (direct) |
| `AUCD` | GpioIo | pin 205 | native GPIO 205 (direct) |
| `AUCD` | ExtendedIrq ×3 | IRQ 202, 203, 170 | **none** — not present anywhere in `GIO0.CIPR`'s 85 entries |

The three `AUCD` `ExtendedIrq` resources don't match any CIPR entry,
unlike every GPIO-backed interrupt resolved elsewhere in this project
(keyboard, touchpad, this same `ASCD` device). That means they aren't
GPIO-routed interrupts at all — most likely internal ADSP
session/channel identifiers the firmware uses for its own bookkeeping,
not physical SoC interrupt lines. Nothing here says what they're for, and
guessing would violate this project's own rule (`docs/evidence-policy.md`:
unknown values stay unknown rather than guessed).

**No WSA amplifier or DMIC device appears anywhere in the DSDT.** No
`WSA88xx`/similar part ID, no second SoundWire peripheral, nothing beyond
the five GPIOs above. This is the same conclusion `docs/audio-
evidence-2026-09-29.md` already drew from Windows PnP (Windows lists no
second SoundWire peripheral either) — now confirmed independently from
the ACPI side, not just the driver-binding side.

## Where this leaves the internal speakers and microphones

Two real, unassigned GPIOs (`191`/`2` on `ASCD`, `204`/`205` on `AUCD`)
plausibly gate something audio-related — a codec/amp reset or enable
line is a reasonable guess by shape, but a guess is exactly what
`gpio-reserved-ranges` being an allow-list is there to
catch, and reserving a pin for the wrong purpose is worse than leaving it
alone. Nothing here proves a purpose, direction, or safe default state.

**This closes out what ACPI evidence can offer for internal speakers/
mics.** The reference Zenbook A16 DTS (`swr0`/`swr3` WSA SoundWire
amplifiers, VA-macro DMICs) doesn't transfer directly, since HP's
hardware shows no evidence of the same WSA-amplifier-over-SoundWire
design at all. The real routing data — which LPASS macro paths HP's
ADSP firmware actually drives, and with what GPIOs — most likely lives in
HP's ACDB/topology binaries (calibration and routing tables, a different
file type than the `adsp*.jsn` servreg configs already checked and not
part of the driver-pack subset committed to this repo), or would need
live introspection of a minimally-probed ADSP audio path on real
hardware, neither of which is available from this checkout today.

**Why stopping here matters, not just "ran out of leads":** GPIOs 191,
2, 204 and 205 are unidentified control lines on live audio hardware — if
one of them is, say, an amplifier enable or a mic-bias line, driving it
with the wrong polarity, at the wrong point in a power sequence, or
leaving it in the wrong idle state is a real way to damage a speaker or
microphone, not just misconfigure software. Everything else this project
has reverse-engineered from GPIO evidence so far (keyboard, touchpad,
touchscreen, lid) resolved cleanly through the same `analyze-acpi-
pdc.py` path with a class of failure that's at worst "doesn't work" —
input pins being wrong doesn't damage the device driving them. Analog
audio power/enable lines don't have that same safety margin. That is a
harder red line than the general "unknown values stay unknown" rule, and
it is the reason this note stops at evidence review with nothing written
to a DT.

## Not changed

No DT or kernel change is proposed from this note. The headset-jack path
stays blocked on upstream SDCA-on-DT support
(`docs/audio-evidence-2026-09-29.md`); the internal speaker/microphone
path stays blocked on missing topology evidence, not on effort — the
GPIO/interrupt evidence available in this repo is now exhausted, not
under-explored.
