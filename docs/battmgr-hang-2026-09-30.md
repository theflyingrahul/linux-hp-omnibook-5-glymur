# Battery Manager Hang, September 30, 2026

## What happened

Kernel `7.3.0-rc2-glymur-7`, "device tree (GPU and USB-A test)", partway
through the USB full/low-speed testing (`docs/usb-c-ports-2026-09-29.md`).
Starting at **12:21:12** and continuing without recovery through at least
**12:35:47** (14+ minutes, still ongoing when captured), every single
read of every `qcom-battmgr-bat` property fails with `-110` (`ETIMEDOUT`):
`manufacturer`, `model_name`, `serial_number`, `status`, `voltage_now`,
`voltage_max_design`, `cycle_count`, `energy_full`, `energy_full_design`,
`charge_full`, `charge_full_design`, `technology`, `temp`, `capacity` —
every property tried, repeatedly, with none ever succeeding. `qcom-
battmgr-ac`, `-usb` and `-wls` all time out identically. `upowerd` first
logged an invalid `NaN` percentage 32 seconds after the failures began
(`captures/2026-09-30-battmgr-hang/journal-sample.txt`), and GNOME's
battery indicator showed **0%** — almost certainly a fallback display for
an invalid/`NaN` reading, not a real measurement, since a genuinely
depleting battery would not make every property (voltage, temperature,
current, capacity) fail identically at the same instant.

## What this is not

- **Not a real battery-empty event.** Every property failing together,
  instantly and totally, is the signature of a dead communication
  channel, not a draining battery.
- **Not a full ADSP/PMIC-GLink failure.** `remoteproc1` (adsp) and
  `remoteproc2` (cdsp) both still report `running`; `remoteproc0` (soccp)
  still `attached`. UCSI — a different client on the same PMIC GLink
  transport — kept responding normally throughout (`ucsi-source-psy-
  pmic_glink.ucsi.01/online` read instantly, no timeout, while `battmgr`
  was mid-failure). The failure is specific to the battery-manager
  service, not the whole PMIC GLink path.
- **Not a shared-lock deadlock in the Linux driver.** `pmic_glink_send()`
  (`drivers/soc/qcom/pmic_glink.c`) takes one mutex (`pg->state_lock`)
  shared by every client (`battmgr`, `ucsi`, `altmode`) on a `pmic_glink`
  instance, but only while *sending* a request; the wait for a reply uses
  a per-client `struct completion` with its own 1-second
  (`wait_for_completion_timeout(..., HZ)`) budget, decoupled from that
  mutex. If the shared send mutex were stuck, UCSI would be stuck too —
  it isn't, which rules this out.

## No PDR/servreg transition logged

`qcom_battmgr_pdr_notify()` sets `battmgr->service_up = false` when the
firmware's battery-manager protection domain reports itself down, which
would normally stop new requests. The journal has no PDR/servreg
state-change message, no `glink`/`qrtr` disconnect, nothing at all around
12:21:12 besides the property-read failures themselves — the transition
that should accompany a detected service crash never showed up. Two
readings fit the evidence:

- The firmware-side battery-manager service actually hung or crashed, but
  the servreg/PDR framework never detected or reported it going down (so
  `service_up` stayed `true` and the driver kept sending requests into a
  service that was no longer answering); or
- The service is technically still marked up but is itself stuck
  (deadlocked, blocked on something else on the PMIC's own MCU) and
  simply isn't processing the battmgr queue, while still answering other
  clients' requests through whatever separates their handling internally.

Either way, the observed failure sits on the firmware side of the PMIC
GLink boundary, not in this Linux driver stack — nothing in
`qcom_battmgr.c` or `pmic_glink.c` looks broken by inspection, and no DT
or kernel change is implicated.

## Timing

The failures began about 6 minutes after this boot (12:15) and roughly 4
minutes after a burst of USB full/low-speed enumeration testing on all
three host controllers (12:15:14–12:17:02,
`docs/usb-c-ports-2026-09-29.md`'s swap-test section), which produced
repeated `dwc3`/`xhci` `WARN`s and role-switch churn. That's a loose
temporal correlation, not a proven cause — USB (dwc3/xhci over the SoC
fabric) and PMIC GLink (RPMSG to the PMIC's own MCU) are architecturally
separate paths, and nothing in the driver code ties them together. Worth
watching for on a future boot: does heavy USB churn reliably precede a
battmgr hang, or is this coincidental.

## What to do

- **Don't trust the battery percentage while this is happening.** If
  unsure of the real charge level, plug in the charger regardless of what
  the UI shows.
- **A reboot is the only recovery tried here** (not yet done — this was
  caught and documented mid-hang, boot still running). Nothing indicates
  it self-recovers; the failure was still continuous after 14+ minutes.
- Not something to chase with a DT or kernel patch from this repository
  without more evidence — this looks like a firmware reliability issue on
  the pre-release PMIC/ADSP stack, the same general class as the USB-C
  charging-negotiation instability found earlier
  (`docs/usb-c-charging-2026-09-29.md`), but a distinct failure mode (a
  fully stuck service, not a collapsing negotiation).
