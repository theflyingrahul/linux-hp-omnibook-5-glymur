# The Camera's USB Controller: `usb_hs`, September 30, 2026

The owner noticed the camera worked on the ACPI boot but not on any
device-tree boot. Read-only follow-up against HP's DSDT (already
captured privately in `.work/`); nothing tested on Linux.

## It's a real USB2 peripheral, not the SoC's own CSI/ISP pipeline

`docs/hardware-topology.md` and `docs/day0-first-pass-2026-09-14.md`
already established this from Windows PnP: "HP True Vision FHD Camera
(USB2 based)... under `USB\VID_30C9&PID_00D9`" — a genuine USB device,
not the SoC's `camss`/`cci` MIPI-CSI pipeline (which also exists in
`glymur.dtsi` but is a separate, much larger subsystem this laptop's
webcam doesn't appear to use).

`docs/usb-a-bringup-2026-09-29.md` had already found its controller:
"`QCOM0FEF` is `usb_hs` @ `0x0a200000`" — but left it there. Today's
DSDT re-read decoded its full `_CRS` (with the same script-based approach
used for `docs/audio-acpi-tree-2026-09-30.md`, not by hand) and searched
`\_SB.PEP0` for its rail votes, the same way `usb_0`/`usb_1`/`usb_2` were
mapped before enabling them.

## Resources, decoded

```
Device (USB4)              // ACPI object name; unrelated to the USB4 protocol
  _HID: QCOM0FEF
  _CID: PNP0D15 (XHCI USB Controller without debug)
  _DEP: \_SB.PEP0

  FixedMemory32: base=0x0a200000 length=0x1000    -> matches usb_hs in glymur.dtsi
  ExtendedIrq: 272
  ExtendedIrq: 278
  ExtendedIrq: 600
  ExtendedIrq: 565
  GpioIo: pin 9 (direct native GPIO, pin < 250 -> no PDC translation needed)

  RHUB.PRT0 only (one downstream port, no PRT1) -- consistent with a
  fixed internal peripheral, not a user-facing connector
  PHYC method present, the same HP tuning-register pattern already
  found on usb_2 (USB-A)
```

## PEP D0 rail votes for `\_SB.USB4`

Same rail-vote table format already used for `usb_0`/`usb_1`/`usb_2`
(`docs/usb-c-ports-2026-09-29.md`), read the same way:

| Rail | Voltage |
|---|---|
| S7F | 1.200 V |
| L15B | 1.800 V |
| LDO8_B | 3.072 V |
| L4H | 1.200 V |
| L2H | 0.880 V |
| L1F | 0.904 V |

All six are the same rail *families* (S7F, L15B, and a handful of LDOs in
the 0.88–3.07 V range) already evidenced and left undeclared for the
working USB-A/USB-C ports today — no new or unfamiliar rail shows up
here.

## Why this is a reasonable next USB target, unlike audio

This is a plain digital USB2 device, the same risk class as the
USB-A/USB-C bring-up already done and working today. Getting a USB
controller's DT wrong means it doesn't enumerate — the same failure mode
already seen (and safely recovered from) with the eUSB2 full/low-speed
gap — not a way to damage the camera module. That's a different safety
profile from the audio GPIOs flagged in `docs/audio-acpi-
tree-2026-09-30.md`, where a wrong guess could drive an unidentified
analog power/enable line incorrectly.

## Not done yet

No DT change is staged. Following the exact precedent from `usb_0`/
`usb_1`/`usb_2`:

- The GPIO on pin 9 needs a role guess resolved by evidence. Checked:
  `usb_hs`'s own PHY (`usb_hs_phy`, `glymur.dtsi`) is `"qcom,glymur-m31-
  eusb2-phy"` — the exact same M31 eUSB2 PHY family as `usb_0`/`usb_1`/
  `usb_2`. None of those three showed an extra GPIO in their ACPI
  resources; this one does. Worth deliberately checking whether that
  GPIO is a repeater enable/detect line before assuming it isn't
  relevant — if so, it would bear directly on today's full/low-speed
  finding (`docs/usb-c-ports-2026-09-29.md`), since it would mean *this*
  internal-only port has a real repeater control line the three exposed
  ports lack entirely.
- No PHY supply, repeater, or `PHYC` register values are declared here
  either, matching the "leave to firmware" approach already used
  successfully for the other three controllers.
- A DTB enabling `usb_hs` + its PHY, alongside the existing test DT,
  would be the next boot-time test — not staged this session.

## Live confirmation, kernel `-9`: both RGB and IR functions present

`usb_hs` was booted (part of `-8`/`-9`'s staged changes). The camera
enumerates as `30c9:00d9 HP True Vision FHD Camera` with four V4L2
nodes, not just one:

```
/dev/video0, video1: "HP True Vision FHD Camera: HP T..." (RGB)
/dev/video2, video3: "HP True Vision FHD Camera: HP I..." (IR)
```

So both the RGB camera and the **IR camera** — previously only
Windows-observed, status "Unknown" in `docs/status.md` — are the same
USB composite device and both come up under Linux once `usb_hs` is
enabled. Not yet tried: an actual frame capture (`v4l2-ctl`/`ffmpeg`
aren't installed on this boot); the device nodes existing with plausible
names is strong but not final proof of a working capture path.
