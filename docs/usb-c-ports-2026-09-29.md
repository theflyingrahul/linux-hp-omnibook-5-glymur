# USB-C Ports and Port Notifications, September 29, 2026

This is the proper fix for the charging drop-outs
(`docs/usb-c-charging-2026-09-29.md`) and the first description of the two
left-hand USB-C ports. Staged as kernel `7.3.0-rc2-glymur-6` plus the
"device tree (GPU and USB-A test)" DTB; untested on the laptop.

## The fault

`pmic_glink_altmode` asks the firmware for USB-C port notifications
(`ALTMODE_PAN_EN`). Each notification asks the OS to set a port's lanes
(USB, DisplayPort or safe mode) and its orientation, and then acknowledge
(`ALTMODE_PAN_ACK`).

The driver sends that acknowledgement only from the worker of a port with
a connector node. For any other port it logs "notification on undefined
port" at debug level and returns. Our device tree described no
connectors, so no notification was ever acknowledged.

In the one run with direct firmware polling (charging-watch, 22:13, kernel
timestamps), the firmware's own connector status never showed a connection
again after the first unacknowledged notification. That was through five
minutes of replugs on both ports.

## Fix, part 1: the kernel always acknowledges

`patches/kernel/upstream/qcom-next/0001-soc-qcom-pmic_glink_altmode-acknowledge-notifications.patch`:

- For a port without a connector node, record it and schedule a work item
  that sends `ALTMODE_PAN_ACK` for that port.
- It needs a work item because the notification callback must not sleep
  and `pmic_glink_altmode_request()` waits for the firmware.
- `devm_work_autocancel()` cancels the work on unbind.

It is board-independent: a device tree that describes fewer ports than the
firmware reports can no longer stall the firmware. HP's firmware reports
three UCSI connectors, the third being the USB-A port.

Checks:

- Mainline (v7.3-rc5 + 11) and qcom-next (tip `e428097a36d`, unchanged
  since 2026-09-28) have no such fix.
- Mainline's `b255c6f4e6` (TBT extradata layout) is already in our tree
  and has no functional effect.
- Compiled with `W=1` without warnings.
- The only source difference between `-5` and `-6`.

## Fix, part 2: describe the USB-C ports

With connector nodes, the driver carries out each notification on the
real PHY before acknowledging it, and UCSI can switch data roles. Mapping
from HP's DSDT:

| Connector (`reg`) | UCSI | `_PLD` | ACPI controller | DT |
|---|---|---|---|---|
| 0, next to the hinge | `UCN0`, connector 1 | `PLD0` | `\_SB.URS0` `QCOM0F8B`, `0x0A600000` | `usb_0`, `usb_0_hsphy`, `usb_0_qmpphy` |
| 1, away from the hinge | `UCN1`, connector 2 | `PLD1` | `\_SB.URS1` `QCOM0F8C`, `0x0A800000` | `usb_1`, `usb_1_hsphy`, `usb_1_qmpphy` |
| (not a USB-C connector) | `UCN2`, connector 3 | `PLD2` | `\_SB.USB2` `QCOM0F9A`, `0x0A000000`, Standard-A | `usb_2` |

- **Which physical port is which** comes from the charging-watch notes:
  connector 2 was the port away from the hinge. The `_PLD` panel field
  says "left" for all three, including the right-hand USB-A port, so it is
  not used.
- **Wiring**, as on the upstream Glymur laptops: high speed to the DWC3
  controller's port 0, SuperSpeed to the QMP USB3/DP PHY. That PHY is the
  orientation and mode switch. The graph was checked in the compiled DTB:
  every link resolves both ways.
- **Data roles:** the controllers keep `usb-role-switch` (dual-role) for
  UCSI to drive.
- **Power (HP's PEP, Mahua branch `LPCE`, D0):**
    - `usb_0`: `gcc_usb30_prim_gdsc` and `gcc_usb_0_phy_gdsc`; rails S7F
      1.2 V, L15B 1.8 V, L3F 0.912 V, L7B 3.072 V, L4H 1.2 V.
    - `usb_1`: `gcc_usb30_sec_gdsc` and `gcc_usb_1_phy_gdsc`; the same
      rails plus L1H 0.936 V.
    - The GDSCs match the controllers' power domains in `glymur.dtsi`.

## Not declared, and why

- **PHY supplies.** The rails are known per controller but not per PHY
  supply, and declaring RPMh regulators risks the regulator core switching
  off shared rails. They stay as firmware left them, as for the working
  USB-A port.
- **eUSB2 repeaters.** HP's ACPI has none. Qualcomm's Windows xHCI filter
  (`QcXhciFilter8480`) looks for an external NXP I²C repeater in each
  controller's resources and logs "External Repeater not present"
  otherwise. `URS0`/`URS1` list only interrupts. The M31 eUSB2 driver
  treats the repeater as optional.
- **DisplayPort over USB-C.** `mdss_dp0`/`dp1` stay disabled.

## What to look for on the first boot

`check-usb.sh` (with USB-C devices plugged in) and `charging-watch.sh`:

- **Charging.** It should survive unplug and replug on both ports: `FW`
  lines follow every plug, the battery goes to `Charging`, and there are
  no "undefined port" lines.
- **USB-C data.** A USB-C stick or hub should enumerate on `usb_0`/`usb_1`
  (`lsusb -t`), with the typec port showing the partner and `data_role`
  host.
- **High speed without a repeater.** A USB 2.0 device on a USB-C port, and
  one on the USB-A port, tests that. If they fail while SuperSpeed works,
  the repeater is the next thing to evidence.
- **Failure mode.** Since this is a DT-only addition over `-6`, the worst
  case is USB-C ports that don't enumerate. Charging is still covered by
  part 1.

## First live test, September 30: the charging fix holds; USB-C data works on one port

`check-usb.sh` and `charging-watch.sh` on kernel `-6`
(`captures/2026-09-30-usb-c-ports/usb-test-111617.txt`,
`captures/2026-09-30-usb-c-charging/charging-watch-111637.txt`).

**Charging: fixed.** Zero "undefined port" lines anywhere in a ~5.5-minute
run with repeated plug/unplug on both ports (was one, followed by total
silence, every prior run). Every plug and unplug now shows up immediately
in both `STATE` (sysfs) and `FW` (direct firmware poll): the battery
tracks real `Charging`/`Discharging`/`Not charging` transitions in step
with the notes ("charging, led on" → `bat=Charging`; "off" →
`bat=Discharging`; and so on through several more cycles). This is the
predicted fix working as designed.

**USB-C data: port1 (away from the hinge) works.** `port1:
data_role=host, power_role=source, opmode=usb_power_delivery,
orientation=reverse, partner=yes`, and a real USB 2.0 hub plus a 128 GB
mass-storage device enumerated on it and read data (`3-1.1 speed=480
Generic Mass Storage Device`, SCSI attach, one partition seen) — the
predicted "high speed without a repeater" case, confirmed. There were a
couple of resets and one transient I/O error before it settled, so it's
not flawless, but it works.

**port0 (hinge side) is unsettled.** It shows `partner=yes`, PD, but
`data_role=device` at the end of the run. The kernel log shows it first
came up in host mode (an `xhci-hcd` registered on `a600000.usb`), tried to
enumerate a low-speed device, failed three times with `error -71`
(`EPROTO`) and "unable to enumerate", then the controller cycled through
`dwc3_host_exit`/re-register a few times before settling with the
role-switch reporting `device`. Not yet known whether that's the far-end
device negotiating the role swap correctly (expected UCSI behavior) or a
real enumeration problem independent of the role — needs a retest with a
known-good USB-C flash drive on port0 specifically, the same way port1
was tested.

**New, minor: a firmware log-spam bug.** `ucsi_glink`, once per port1
reconnect: `con2: Firmware bug: duplicate partner altmode SVID 0xff01 at
offset 1..29, ignoring but please contact the BIOS vendor to fix this
issue.` — the firmware reports the same alternate-mode SVID dozens of
times per connector-status read; the kernel already handles it
(de-duplicates and logs), so this is cosmetic journal noise from HP's
firmware, not a functional bug. Not worth chasing from this repository.
