# eUSB2 Repeaters and the Camera Controller, September 30, 2026

Follow-up to the full/low-speed failure on all three host ports
(`docs/usb-c-ports-2026-09-29.md`, swap-test section). Staged in the
"device tree (GPU and USB-A test)" DTB of kernel `7.3.0-rc2-glymur-8`;
not yet booted.

## Why the repeaters, and why now

- On kernel `-7`, a USB mouse failed on `usb_0`, `usb_1` and `usb_2`
  (`error -71`, then "Device not responding to setup address"). High-speed
  and SuperSpeed devices worked on the same ports in the same boot.
- **The hardware can do full speed.** On the ACPI boot, where Linux never
  touches the USB PHYs and they stay as firmware set them, the USB-A port
  ran a Dell receiver at 12 Mb/s (`docs/status.md`, "Right USB-A"). So the
  device-tree boot breaks full speed. The ports themselves are fine.
- An eUSB2 PHY reaches a USB 2 connector only through a repeater, so these
  ports have repeaters, and high speed passing proves they are powered.
  What Linux does not do without a repeater node:
    - The M31 eUSB2 PHY driver calls `phy_init()` and `phy_set_mode()` on
      its repeater. With no repeater node, neither runs.
    - In host mode, the repeater driver (`phy-qcom-eusb2-repeater.c`)
      forces the repeater's 19.2 MHz clock on (`EUSB2_FORCE_EN_5`/`_VAL_5`,
      an eUSB 1.2 "CM.Lx" workaround, in the driver since its first
      version). It also enables the repeater and writes its tuning (`IUSB2`,
      `SQUELCH_U`, `USB2_SLEW`, `USB2_PREEM` for the SMB2370).
    - The PHY driver also resets the PHY at `phy_init()`, which the ACPI
      boot never does.
- Whether the missing host-mode setup is the whole cause is not proven. It
  is the documented difference between a working and a non-working
  configuration of the same hardware, and the upstream configuration for
  this SoC.

## Where the repeaters are

- **HP's firmware tables don't say.**
    - HP's ACPI has no repeater device.
    - The `PHYC` tuning methods of `\_SB.URS0.USB0` and `UFN0` return empty
      packages.
    - `\_SB.PMIC.PMCF` maps PMIC slots to SPMI slave IDs without naming
      models, and `\_SB.SPMI.CONF` describes three buses without devices.
    - Windows binds its stock `USBXHCI`/`UrsSynopsys` drivers with no
      lower filter. Qualcomm's `QcXhciFilter8480` INF targets these
      controllers but holds no repeater settings; its binary has no
      repeater strings.
    - So firmware and the PMIC driver set the repeaters up, not ACPI.
- **Qualcomm's reference designs do.** The Glymur CRD (`glymur-crd.dtsi`,
  which `mahua-crd.dts` includes) and the ASUS Zenbook A16 both put
  SMB2370 PMICs on SPMI bus 2 (`smb2370.dtsi`: SID 9 "J", SID 10 "K", SID
  11 "L", disabled). Each has an eUSB2 repeater at `0xfd00`. The CRD links
  `usb_0_hsphy` → J and `usb_1_hsphy` → K, with `vdd18` from L15B and
  `vdd3` from L7B.
- **HP's power votes fit.** HP's PEP D0 votes for `usb_0` and `usb_1`
  include **L15B 1.8 V** and **L7B 3.072 V**
  (`docs/usb-c-ports-2026-09-29.md`), the two rails the CRD gives these
  repeaters. `usb_2` (USB-A) votes the same two rails, so it most likely
  has one too.

## What `-8` stages

1. **`patches/kernel/upstream/qcom-next/0003`** ("phy: qcom:
   eusb2-repeater: check the parent PMIC before using it"). For the
   SMB2370, the repeater driver now checks that its parent PMIC reports
   subtype 0x5f (`SMB2370_SUBTYPE`, read by the SPMI PMIC core from the
   PMIC's revision registers at probe) before it registers the PHY. It
   logs `parent PMIC subtype …` either way. If a different PMIC, or
   none, sits at that SID, the repeater refuses to probe and nothing
   writes to it. The patch is generic and a candidate for upstream.
2. **The USB test DTS** declares SMB2370 PMICs at SPMI bus 2 SIDs 9, 10
   and 11, each with only its repeater child (none of the CRD's BCL
   sensor). It links `usb_0_hsphy` → SID 9 and `usb_1_hsphy` → SID 10, as
   on the CRD.
    - No supplies are declared: the repeaters get dummy regulators, and
      the rails stay as firmware left them, as for the PHYs. No tuning
      overrides: the driver's SMB2370 defaults, as on the CRD.
    - SID 11 is linked to nothing. Its repeater probes, which identifies
      the PMIC, but is never initialized, so nothing is written to it.
    - `usb_2` stays without a repeater. The USB-A port, which the owner
      boots and stages from, keeps exactly its `-7` setup.
3. **The internal camera's controller.** `usb_hs` (`\_SB.USB4`, `QCOM0FEF`)
   and `usb_hs_phy` are enabled, host only. See
   `docs/camera-usb-controller-2026-09-30.md`.
    - Its base (`0x0a200000`) matches ACPI, and so do its interrupts: GIC
      SPI 240 and 246 are ACPI 272 and 278.
    - The ACPI GPIO 9 stays unused and reserved; its role is unknown.
    - The camera module may be unpowered, or need a repeater of its own;
      then it does not enumerate, with no other effect.

## Failure modes, all recoverable by booting another entry

- **A PMIC at SID 9 or 10 is not an SMB2370:** that repeater refuses, and
  its PHY waits for it forever. That USB-C port loses data for the boot.
  Charging (PMIC GLink) and the other ports are unaffected.
- **SPMI bus 2 is not usable from Linux:** same result for both USB-C
  ports.
- **The repeaters identify, but full speed still fails:** the cause is
  elsewhere (PHY reset, repeater tuning or mode). The log then shows
  whether `phy_set_mode` ran.
- **The J/K mapping is swapped on HP's board:** the tuning is the same for
  both, and both ports are hosts for a mouse, so this is unlikely to show.
  The dual-role paths (host ↔ device) would then write the host-mode
  clock setting to the other port's repeater.

## What to look for

`sudo bash ~/check-usb.sh` (updated) prints:
- the SPMI devices and each repeater's `parent PMIC subtype` line;
- the camera (`lsusb -d 30c9:`, video devices);
- full kernel warnings.

A mouse in each USB-C port should now enumerate. On USB-A it is still
expected to fail.
