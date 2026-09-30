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

## It recurred on a completely fresh reboot — this is deterministic, not a fluke

Rebooted (kernel `-11`, same DTB). Within ~8 minutes, `check-usb.sh` hit
the identical crash signature a second time, this time with a much
clearer mechanism:

```
refcount_t: underflow; use-after-free.
WARNING: lib/refcount.c:28 ...
 kobject_put+0x208/0x340
 software_node_notify_remove+0x104/0x140
 device_del+0x16c/0x3c0
 usb_disconnect+0x314/0x350
 usb_remove_hcd+0x18c/0x2a0
 xhci_plat_remove+0x150/0x1b0 [xhci_plat_hcd]
 ...
 dwc3_host_exit+0x3c/0x98 [dwc3]
 __dwc3_set_mode+0x218/0x430 [dwc3]

Unable to handle kernel paging request at virtual address 002f7365646f6e5f
[002f7365646f6e5f] address between user and kernel address ranges
Internal error: Oops: 0000000096000004 [#1]  SMP
 pc : software_node_property_present+0x54/0xe0
 lr : fwnode_property_present+0x84/0x100
 ... xhci_plat_probe ...
```

This is a complete, unambiguous use-after-free, not a one-off fault:

1. **Tearing down** the xhci platform device for a USB-C controller
   (`xhci_plat_remove` → `usb_remove_hcd` → `device_del` →
   `software_node_notify_remove` → `kobject_put`) hits a **refcount
   underflow** — the software_node's reference count was already wrong
   before this removal, exactly what a double-registration (the boot-time
   "cannot create duplicate filename" bug) would cause.
2. Moments later, the **next probe** of a controller
   (`xhci_plat_probe` → `fwnode_property_present` →
   `software_node_property_present`) dereferences a **freed/corrupted
   fwnode** and faults. The faulting address, decoded as ASCII, spells out
   a fragment of the string `"...node/s..."` — this is memory that used
   to hold `"software_node"`-related string data, now being read back as
   if it were a live pointer. Textbook use-after-free.

**This is deterministic, not intermittent**: it reproduced on the very
next boot, from the very same trigger (a `__dwc3_set_mode` role-switch
cycle happening during normal `check-usb.sh` use, no unusual action
taken). The boot-time "cannot create duplicate filename" bug still
appeared too, on `a000000.usb` this time. **A reboot does not avoid this
bug** — it only resets the clock until the next role-switch cycle hits
it again. Evidence:
`captures/2026-09-30-dwc3-crash/second-crash-timeline.txt`,
`usb-test-232629-after-reboot.txt`, `usb-test-232702-after-reboot-crash.txt`.

**Unaffected, confirmed again on the fresh boot**: `check-mesa.sh`
(`mesa-test-231958-after-reboot.txt`) and `check-ec.sh`
(`ec-test-232119-after-reboot.txt`) both ran cleanly, before the crash
hit — GPU/Mesa and the EC are not implicated.

**Revised advice:** this is a real, reproducible kernel bug in how
`software_node` is registered/reference-counted for the USB-C dwc3
controllers on this consolidated test DTB — every time a host-mode
role-switch tears down and rebuilds the xhci platform device, it's a
coin flip whether the next access hits the corrupted node. Until this is
fixed at the kernel level, avoid repeated USB-C plug/unplug or role
switches on this DT; a reboot resets the immediate symptoms but not the
underlying bug.

## Fixed in kernel `-12`

A new kernel was installed and the same tests re-run
(`captures/2026-09-30-dwc3-crash/*-kernel12.txt`). Clean across the
board:

- **Zero occurrences** of `Internal error`, `refcount_t: underflow`, or
  `cannot create duplicate filename` anywhere in this boot's kernel log
  — the only `WARNING` present is the pre-existing, unrelated
  `kernel/sched/idle.c:269` one seen since the start of this project.
- **Both USB-C controllers exercised a host-mode role-switch and
  survived**: `a800000.usb` (`usb_1`) got a fresh `xhci-hcd` at
  `23:43:05`, `a600000.usb` (`usb_0`) at `23:43:48` — the exact
  transition that crashed twice before now completes cleanly, twice, in
  the same boot.
- **The battery manager is healthy**: `qcom-battmgr-bat/capacity` reads
  `18` instantly, no timeout — first clean reading after two hangs this
  session.
- `check-mesa.sh` and `check-ec.sh` both still pass (GPU clock genuinely
  scales to 1.35 GHz under load; fan/thermistors read correctly, backlight
  timeout unaffected).

Root cause and fix aren't independently confirmed from this checkout
(whatever changed between the crashing kernel and `-12` isn't yet
reflected in this repo's own commits), but the observed behavior —
exactly the two previously-reliable crash triggers now both completing
without incident, and the one-boot-old battmgr hang also gone — is a
strong live signal this is resolved. Worth a few more boots of ordinary
use (unplug/replug cycles especially) before calling it fully closed.
