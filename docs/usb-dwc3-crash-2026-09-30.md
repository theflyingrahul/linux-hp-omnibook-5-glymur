# A Real Kernel Crash: dwc3 Role-Switch, USB-C Port1 Dead Since, Battery Manager Hung Again

Kernel `7.3.0-rc2-glymur-11`, the consolidated "test" DTB
(`mahua-hp-omnibook-5-bf1xxx-test.dtb`, replacing the separate `-usb.dtb`
— model string is now just "HP OmniBook 5 Laptop 16-bf1xxx", same
GPU+USB+EC content as before). The owner reported: a mouse worked once on
USB-C, is broken now; no USB port seems functional; the battery reads
0%. Root-caused live, with the machine still in the broken state while
this was written. Evidence: `captures/2026-09-30-dwc3-crash/
crash-timeline.txt`, `captures/2026-09-30-dwc3-crash/usb-test-*.txt`
(three `check-usb.sh` runs taken after the crash).

## The actual sequence

**1. A real double-registration bug exists at boot, on all three dwc3
controllers, not just the USB-C ones:**

```
sysfs: cannot create duplicate filename '.../a600000.usb/software_node'
qcom_pmic_glink pmic-glink: Failed to create device link (0x180) with supplier fd5000.phy for /pmic-glink/connector@0
qcom_pmic_glink pmic-glink: Failed to create device link (0x180) with supplier fde000.phy for /pmic-glink/connector@1
sysfs: cannot create duplicate filename '.../a800000.usb/software_node'
qcom_pmic_glink pmic-glink: Failed to create device link (0x180) with supplier a800000.usb for /pmic-glink/connector@1
sysfs: cannot create duplicate filename '.../a600000.usb/software_node'
qcom_pmic_glink pmic-glink: Failed to create device link (0x180) with supplier a600000.usb for /pmic-glink/connector@0
sysfs: cannot create duplicate filename '.../a000000.usb/software_node'
```

`a600000.usb` (`usb_0`) hits the duplicate-filename error *twice*,
`a800000.usb` (`usb_1`) once, and even `a000000.usb` (`usb_2`, USB-A,
which isn't Type-C and has no `pmic-glink` connector at all) hits it
once too. This isn't specific to the new USB-C connector graph wiring —
it looks like a broader software_node/fwnode double-registration problem
across all three dwc3 controllers in this consolidated DTB, severe
enough to break `pmic_glink`'s own supplier device-links to the Type-C
PHYs and connectors. **This alone didn't stop the boot** — `usb_0` and
`usb_1` both still enumerated normally minutes later (a Dell wireless
receiver came up cleanly on `usb_1` at boot), so whatever's duplicated
didn't immediately break device probing.

**2. ~13 seconds after the Dell receiver enumerated, a real CPU
exception hit a USB-C role-switch:**

```
Internal error: SP/PC alignment exception: 000000008a000000 [#1]  SMP
...
Workqueue: events_freezable __dwc3_set_mode [dwc3]
pc : 0x405a60d2800022
lr : fwnode_property_read_bool+0x84/0x100
Call trace:
 0x405a60d2800022 (P)
 device_property_read_bool+0x28/0x78
 xhci_plat_probe+0x3f0/0x860 [xhci_plat_hcd]
 xhci_generic_plat_probe+0xac/0x120 [xhci_plat_hcd]
 platform_probe+0x70/0x128
 ... driver_probe_device ... device_add ... platform_device_add+0x108/0x2d8
 dwc3_host_init+0x4a4/0x680 [dwc3]
 __dwc3_set_mode+0x100/0x430 [dwc3]
```

The program counter (`pc`) is a garbage, non-kernel address — not a
normal fault, a jump to corrupted memory, inside
`fwnode_property_read_bool()` called from a *freshly re-created* xhci
platform device (`dwc3_host_init()` builds a new one every time a
controller (re-)enters host mode). This is the textbook shape of a
stale/corrupted fwnode: the boot-time double-registration above is the
one thing already known to be wrong with these controllers' fwnodes, and
this is a second, later probe of the same controller hitting whatever
that left behind. Not proven beyond the circumstantial link — but it's
the only irregularity on record for this exact code path, and the crash
is precisely where a corrupted fwnode would bite.

This was recorded as oops `[#1]` — the kernel survived (it's a kworker
crash, not a full panic) but tainted itself (`W`, and now the oops bit
too).

**3. `usb_1` (the port the crashing role-switch was for) has had no
`xhci-hcd` since.** Live, right now: `a600000.usb` (`usb_0`) still has an
`xhci-hcd.4.auto` child; `a800000.usb` (`usb_1`) has none. Three separate
`check-usb.sh` runs after the crash all agree: `port0: partner=yes,
opmode=3.0A` (power only, no data device tested), `port1: partner=no`,
every time. That's "the mouse came up once, broken now" — the receiver
was on `usb_1`, which is the controller whose role-switch crashed and
never recovered.

**4. Within the same ~26-second window, UCSI and the battery manager
both started failing too:**

```
22:45:22.75  Internal error: SP/PC alignment exception ... __dwc3_set_mode
22:45:32.82  ucsi_glink: GET_CURRENT_CAM command failed
22:45:39.99  qcom-battmgr-bat: driver failed to report `manufacturer' property: -110
22:45:43–46  (status/model_name/serial_number, same pattern as every prior battmgr hang)
22:45:48.18  ucsi_glink: GET_CONNECTOR_STATUS failed (-110)
```

**UCSI recovered on its own within the same boot** (querying it live now
returns instantly, no timeout). **The battery manager did not** — still
hung right now, `cat .../capacity` still times out, matching every
previous battmgr hang this project has seen: once it starts, it doesn't
recover without a reboot. The tight time correlation with the dwc3 crash
is circumstantial, not proven causal (PMIC GLink and the SoC's own USB
fabric are architecturally separate paths), but it's the same shape as
this session's very first battmgr hang, and this time there's an actual
kernel exception to point at happening right in the middle of the
failure window, not just silence beforehand. **The owner's "battery says
0%" is the same false reading as before**: every property fails
identically and at once, which a real draining battery doesn't do.

## What's confirmed still working, despite this

- `usb_2` (USB-A) and `usb_hs` (the camera): on separate dwc3 instances
  from the crashing one, and both still enumerate — the camera and the
  boot stick are both visible in `lsusb` right now.
- GPU/Mesa (`check-mesa.sh`, run at 22:38, before the crash) and the EC
  (`check-ec.sh`, run at 22:40, also before) were both fully normal —
  this is not a general system meltdown, it's isolated to the USB-C
  role-switch path and its PMIC-GLink aftermath.
- `usb_0` (`port0`) still has a live `xhci-hcd`, though no actual data
  device has been tested on it since the crash — only a power-only
  partner.

## Not fixed this session

This needs a real kernel-level fix (tracking down why `software_node`
gets registered twice for these controllers, most likely in how the new
`ports`/`endpoint` OF-graph linkage combines with `usb-role-switch` in
this consolidated DTB) — not something to patch blind without reproducing
it under more controlled conditions (ideally with a fwnode-refcount or
KASAN-enabled debug kernel). Recorded here as a real, reproducible crash
with a full backtrace for whoever picks this up next.

**Immediate advice:** a reboot is the only way back to a fully working
system — `usb_1`'s role-switch state and the battery manager hang have
both shown no sign of self-recovery. Don't trust the battery percentage
in the meantime.
