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
`data_role=device` at the end of the run. The device plugged in was a
plain USB mouse (low-speed, the class of device HP's own driver stack has
no reason to route specially) — a simple HID device that ordinarily
enumerates without incident, which weighs against "the far end negotiated
a role swap" and toward a real host-mode enumeration problem on this
controller. The kernel log shows it first came up in host mode (an
`xhci-hcd` registered on `a600000.usb`), tried three times to read the
mouse's device descriptor, failed each time with `error -71` (`EPROTO`)
and "unable to enumerate", then the controller cycled through
`dwc3_host_exit`/re-register a few times before settling with the
role-switch reporting `device`. Needs a retest with the same mouse (or
another known-good low-speed device) on port0 specifically, the same way
port1 was tested, ideally also trying a USB-C storage device to see if
the failure is speed/class-specific.

**New, minor: a firmware log-spam bug.** `ucsi_glink`, once per port1
reconnect: `con2: Firmware bug: duplicate partner altmode SVID 0xff01 at
offset 1..29, ignoring but please contact the BIOS vendor to fix this
issue.` — the firmware reports the same alternate-mode SVID dozens of
times per connector-status read; the kernel already handles it
(de-duplicates and logs), so this is cosmetic journal noise from HP's
firmware, not a functional bug. Not worth chasing from this repository.

## Second read of the September 30 logs: corrections and missed findings

A line-by-line pass over `usb-test-111617.txt` and
`charging-watch-111637.txt` changes two conclusions above and adds three
findings.

**Correction 1: port0 ending as `device` was the charger, not a failure.**
At the end of `check-usb.sh`, port0 reads `power_role=sink`,
`data_role=device`, PD, and 20 seconds later `charging-watch.sh` shows the
charger on it (`01:on=1,PD,3250000uA`, `bat=Charging`). A port with a PD
charger is a sink and USB device; that is correct behaviour. The mouse
failures before it are real, but the role change is the owner swapping
the mouse for the charger.

**Correction 2: the evidence cannot yet tell a bad port from a bad
speed.** The only device tried on port0 was **low-speed** (the mouse:
`new low-speed USB device`, then `error -71` twice, re-tried twice, `unable
to enumerate`). The only device tried on port1 was **high-speed** (the
hub). The two ports use the same M31 eUSB2 PHY design. On eUSB2, low and
full speed depend on the repeater translating signalling; we declare no
repeater and rely on the firmware's setup. So "low speed fails
everywhere" fits the log as well as "port0 fails". Test: swap the mouse
and the hub between the ports. The mouse also fails on port1 → a
low-speed or repeater problem. The hub also fails on port0 → port0.
`check-usb.sh` now says this and labels each device with its controller.

**Missed 1: a kernel WARN on every host-to-device role switch.** Each time
a controller left host mode (11:13:46 on `a800000`, 11:14:57 and 11:15:18
on `a600000`), the log has a module list and a trace through
`__dwc3_set_mode` → `dwc3_host_exit` → `xhci_plat_remove`: the body of a
`WARNING`, whose first line the old grep filter dropped. On `a600000`
it comes with `kernfs: can not remove 'usb5', no directory` and `...
'xhci-hcd.4.auto', no directory`. The names match
`typec_partner_unlink_device()`, which removes a link named after the USB
device from the Type-C partner, so the partner's sysfs directory was
already gone when the xHCI host was torn down: likely an ordering race
between UCSI partner removal and the dwc3 role switch. The kernel is now
tainted `W` (visible in the hung-task report). There is no functional
effect seen (both ports re-enumerated afterwards), and no patch until the
full WARNING (file and line) is captured: `check-usb.sh` now prints
warnings in full.

**Missed 2: charging through the hub cost the hub's data.** At 11:17:15
the owner plugged the charger into the hub on port1 ("connected to usb
hub's port, looks like charging"). The hub dropped and re-attached, the
host came back and re-enumerated the hub and stick (698.4 s), then port1
dropped again. It reattached with the laptop as **sink** and the firmware
reporting the partner as **DFP** (`con2 ... dir=0 partner=1`), and the
xHCI host was removed and not re-added. So while charging through the
hub, the laptop was the USB device and the stick was gone. With PD, the
power source starts out as the data host, and staying host after the
hub becomes the source needs a data-role swap. Windows presumably gets
one; here nothing asked. Next test: with the charger in the hub,
`echo host | sudo tee /sys/class/typec/port1/data_role` (a UCSI DR_Swap
request), then see if the stick comes back.

**Missed 3: SuperSpeed on USB-C is still untested.** The stick on port1
ran at 480 Mb/s behind a USB 2.0 hub; the 10 Gb/s root hubs on both USB-C
controllers had nothing attached. A USB 3 stick directly in each port
(both orientations) is needed to test the QMP PHY lanes and the
orientation switch.

**Minor:**
- One read error at the stick's last sectors (`I/O error, dev sdb, sector
  249737212`) after two resets, right after attach. That is common with
  cheap "Generic" flash probing its end and says nothing about the port on
  its own.
- The firmware lists the same partner alternate mode (SVID 0xff01) 29
  times for con2; the kernel ignores the duplicates (noise only).
- Ubuntu's AppArmor profile for `lsusb` denies reading
  `/sys/devices/platform/soc@0/*.usb/uevent`; `lsusb -t` still works. Noise
  only; `check-usb.sh` now filters it.
