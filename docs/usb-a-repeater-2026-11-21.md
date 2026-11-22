# The USB-A port's eUSB2 repeater, November 21, 2026

On `-23`, full-speed devices failed on the USB-A port: a receiver worked for
about a minute, then reset every few seconds and read corrupted descriptors
(`docs/runbook-results-23-2026-11-21.md`). High speed and SuperSpeed are
fine. The port's eUSB2 PHY (`usb_2_hsphy`, M31 at `0x088e0000`) has no
repeater in our device tree.

On USB-C, full and low speed failed the same way until the two SMB2370
repeaters were described (`-8`) and powered (`-19` to `-23`). That makes a
missing repeater the likely cause here too. An eUSB2 PHY reaches a USB 2
connector only through a repeater, so there is one. Full speed worked on this
port on the ACPI boot, where Linux never resets the PHY
(`docs/eusb2-repeater-2026-09-30.md`).

## What the other Glymur and Mahua boards have

From Linux 7.4's device trees:

| Board | `usb_2_hsphy`'s repeater | Other USB 2 repeaters |
| --- | --- | --- |
| Lenovo Yoga Slim 7x (Glymur) | SMB2370 "L", SPMI SID 11 | — |
| Lenovo ThinkPad T14s Gen 7 (Mahua) | NXP PTN3222 on `i2c5` at `0x4f`, reset TLMM 40 | PTN3222 on `i2c5` at `0x43`, `0x4b`, `0x47` |
| Glymur CRD, ASUS Zenbook A14 and A16 | `usb_2` not used | PTN3222 on `i2c5` at `0x43`/`0x4f`, reset TLMM 8 or 184 |

## What HP's tables say

- **No SMB2370 "L".** HP's power tables vote rails on the PMICs they use.
  "J" and "K" appear: the two SMB2370s behind the USB-C repeaters at SID 9
  and 10. "L" never does. On `-8` a probe of SID 11 failed with `-5`.
- **`i2c5` is HP's `I2C6`** (`QCOM0F10`, `_UID` 6, `QUP_0_SE_5` at
  `0x00b94000`). It has its own clock table, and Windows binds it ("Qualcomm(R)
  I2C Bus Device", `ACPI\QCOM0F10\6`). Three devices depend on it:
    - `PML0` (`QCOM0FC6`, "Power Management PML0", present) at I2C address
      `0x08`, 100 kHz;
    - the SAR sensors `QCOM0F9E` and `QCOM0F9F` (`SAR1`, `SAR2`), present only
      on some platform variants.

  That is the CRD's `i2c5` layout: its PM8010 camera PMIC is `pmic@8` there,
  next to its PTN3222.
- **No repeater in ACPI or Windows.** Nothing in the DSDT, the SSDTs, Windows'
  device list or the driver pack's INF files names a PTN3222, an eUSB2
  repeater or a redriver. A PTN3222 needs no OS driver on Windows.

So the likely part is a PTN3222 on `i2c5`, as on the T14s.

## What Linux's PTN3222 driver does

`phy-nxp-ptn3222.c` writes no registers. Its `phy_init()` enables the two
supplies (`vdd3v3`, `vdd1v8`) and releases the reset line; `phy_exit()`
asserts it. With the node, the M31 PHY driver resets the repeater in step
with the PHY. Without it, the repeater keeps whatever state it had when Linux
reset the PHY. That would fit high speed renegotiating while full speed
breaks, but it is not proven.

The reset line is unknown. Pin 40 on the T14s, and 8 and 184 on the CRD and
Zenbooks, are all firmware-owned on this laptop: they are outside our GPIO
allow-list, and HP's tables do not name them. A node without a reset line
would change nothing, because the driver would only enable supplies that
are already on.

## Kernel `-26`: find it first

The test device tree enables `i2c5` at HP's 100 kHz, with no devices on it,
and allows its two pins, GPIO 20 and 21 (`qup0_se5`). The evidence for them
is that Windows drives this bus. `check-usb.sh --repeater` then:
- read-probes only `0x40` to `0x4f`, so `PML0` at `0x08` is never touched;
- byte-dumps registers `0x00`–`0x3f` of every address that answers.

What the answer decides:
- **A device at a PTN3222 address:** describe it (its supplies from HP's
  USB 2 votes: L15B 1.8 V and L7B 3.072 V), then find its reset line. The
  candidates are the Glymur reference pins, checked one at a time against
  HP's evidence.
- **Nothing between 0x40 and 0x4f:** not a PTN3222 on this bus. Next would be
  the UEFI firmware's USB initialisation.
