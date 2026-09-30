# USB-C Charging: Plugged In, Not Charging, September 29, 2026

> **Second correction (later the same day).** The `-4` session's own
> `power-supplies.txt` shows the battery **charging at 40 W** over PD on
> connector 2. The `qcom-battmgr-ac`/`-usb` `ONLINE=0` values cited below
> do not track the charger on this platform. Charging on the device-tree
> boot is intermittent, not absent. See "Re-reading the `-4` captures"
> near the end.

> **Correction (same day, from the pinned source).** The observations below
> contradict each other, and the causal chain ("no PDOs fetched, so no PD
> contract, so no charging") does not hold.
>
> - `ucsi_psy_get_online()` reports `ONLINE=1` whenever the connector is
>   connected and sinking. `ucsi_psy_get_usb_type()` reports `PD` whenever
>   the power operation mode is PD (`drivers/usb/typec/ucsi/psy.c`). The
>   typec attributes come from the same cached connector status. A single
>   snapshot cannot show port1 with a partner, a sink role and
>   `power_operation_mode=usb_power_delivery` while both UCSI supplies
>   show `ONLINE=0` and `USB_TYPE=[C]`. The reads came from different
>   moments, or the typec state is stale from a missed UCSI notification.
> - `power_operation_mode=usb_power_delivery` (UCSI power operation mode 3)
>   means an explicit PD contract *was* reached.
> - Linux reading PDOs over UCSI (`ucsi_get_pdos()`) is informational only.
>   The PD contract is negotiated by the PMIC/charger firmware, so a skipped
>   `GET_PDOS` cannot stop charging. The `UCSI_CAP_PDO_DETAILS` explanation
>   may still be why no PDOs appear, but it is not why the battery
>   discharges.
>
> What stands: the charger firmware's own view, `qcom-battmgr-ac`/`-usb`
> `ONLINE=0`, and the battery discharging at about 8.6 W. The cause is
> open. Next test, on one boot: record the charger (wattage, which port);
> take a timestamped snapshot of typec, all power supplies and `journalctl
> -k` together; unplug, wait, replug, and snapshot again. Also note whether
> the charger was plugged in before or after boot.

Reported live: charger plugged in on the full DT (kernel `7.3.0-rc2-glymur-4`,
same boot as `docs/edp-display-working-2026-09-29.md`), no charging LED, and
the battery kept discharging. This is a scan of every layer between the
physical port and the battery, done live (no reboot).

## Result: the charger is detected at the Type-C/PD level, but no charge happens

`qcom-battmgr-bat`: `POWER_SUPPLY_STATUS=Discharging`,
`POWER_SUPPLY_POWER_NOW=-8597000` (discharging ~8.6 W). `qcom-battmgr-ac`
and `qcom-battmgr-usb`: both `ONLINE=0`. Both `ucsi-source-psy-*` supplies:
`STATUS=Not charging`, `ONLINE=0`, `USB_TYPE=[C] PD PD_PPS` (current value
`C`, meaning no PD contract — PD/PD_PPS are just the listed capabilities,
not what's active).

But one port does see a partner:

- `/sys/class/typec/port0`: no partner, `power_operation_mode=default`.
  Nothing attached here (or its detection path is dead — can't tell which
  from one boot).
- `/sys/class/typec/port1`: **has `port1-partner`**, `orientation=normal`,
  `power_operation_mode=usb_power_delivery`, `data_role=host [device]`
  (we are the device/sink side), `power_role=source [sink]` (we are
  sink). The partner reports `supports_usb_power_delivery=yes`,
  `usb_power_delivery_revision=1.0` (ours is 3.1 — a normal, backward-
  compatible mismatch). This is real attach detection: UCSI over PMIC
  GLink sees the cable, negotiates orientation, and classifies the
  partner as PD-capable, in the correct sink role for a laptop being
  charged.

So the physical/orientation/role layer works. The break is one layer up:
**no Power Data Objects (PDOs) were ever fetched**, from either side.
`/sys/class/usb_power_delivery/pd0` (our own capabilities) and `pd1` (the
partner's, under `port1-partner/pd1`) both exist only as bare directories —
no `source-capabilities`/`sink-capabilities` children, which is what would
list the actual voltage/current options. `dmesg`/`journalctl -k -b` has
**zero** UCSI-related lines of any kind, not even an error.

## Why: the firmware's UCSI capability response doesn't advertise PDO details

Traced into the pinned kernel source
(`drivers/usb/typec/ucsi/ucsi.c`, `ucsi_get_pdos()`):

```c
if (!(ucsi->cap.features & UCSI_CAP_PDO_DETAILS))
    return 0;
```

If the UCSI `GET_CAPABILITY` response (from the PPM — here, firmware
behind PMIC GLink) doesn't set `UCSI_CAP_PDO_DETAILS`, the kernel silently
skips PDO retrieval for both source and sink, on both our side and the
partner's — no error, nothing logged. That is exactly what was observed:
no PDO objects anywhere, and total silence in the log, which only happens
on this early-return path (a real `UCSI_GET_PDOS` failure would log
`dev_err(ucsi->dev, "UCSI_GET_PDOS failed (%d)\n", ...)`, and there is none).

This is a firmware capability gap, not a DT or driver bug reachable from
this repository:
`drivers/usb/typec/ucsi/ucsi_glink.c` already has a platform quirk table
keyed by the `pmic-glink` compatible string, and **our exact compatible is
in it**:

```c
static unsigned long quirk_sm8450 = UCSI_DELAY_DEVICE_PDOS;
static const struct of_device_id pmic_glink_ucsi_of_quirks[] = {
	{ .compatible = "qcom,glymur-pmic-glink", .data = &quirk_sm8450, },
	...
```

`UCSI_DELAY_DEVICE_PDOS` only changes *when* our own device PDOs are read
relative to registration; it does not set `UCSI_NO_PARTNER_PDOS` and does
not touch `UCSI_CAP_PDO_DETAILS`. So this platform is already known to
upstream as PDO-quirky in some way, but not specifically for a missing
`UCSI_CAP_PDO_DETAILS` bit, and nothing in the DTS controls that bit — it
comes from firmware's own `GET_CAPABILITY` answer.

## Why there's no charging LED

Independently expected, not new: the charging LED is EC-controlled
(`docs/status.md`'s established EC gap), and the EC (IC10) has no node in
this device tree — `/sys/bus/i2c/devices/` has no `0x76` device on any
bus, and `/sys/class/leds/` has only the keyboard lock-key LEDs
(`input9::capslock` etc.), no charging indicator. This would be true even
if charging worked correctly.

## What this is, and isn't

- This is not a wiring or DT mistake to fix here: the attach/orientation/
  role layer (which *is* DT/driver-reachable) works correctly. The break
  is in what firmware reports for UCSI capabilities, one layer above
  anything in this repository's device tree.
- It does not rule out that charging works correctly under ACPI/Windows,
  or that a different PMIC GLink firmware capability response would fix
  it — that would need Qualcomm/HP firmware, not a kernel or DT change.
- Not yet checked: whether the ACPI boot path (`\_SB.PMGK`/`\_SB.ABD`,
  the same firmware-served path Windows uses) shows the same PDO gap. If
  ACPI-mode charging also fails, the gap is upstream of any Linux driver
  choice; if it works there, the difference is worth isolating (possibly
  a different UCSI capability answer requested via GLink vs. ACPI
  `_DSM`/`_PSR`).

## The unplug/replug test (kernel `-5`, GPU test DT): total silence, not partial

Two `check-gpu-test.sh --charging` attempts, from the "device tree (GPU
test)" boot (`docs/gpu-bringup-run1-2026-09-29.md`), full logs (identifiers
masked) in `captures/2026-09-29-gpu-bringup-run1/`:

- `gpu-test-20260929T170344.txt`: stopped right after the first prompt
  ("Unplug the charger, then press Enter.") — an aborted attempt, not a
  result.
- `gpu-test-20260929T170406.txt`: completed the full sequence — a baseline
  snapshot, "Unplug the charger" (10 s settle), a snapshot, "Plug the
  charger into the same port" (20 s settle), a final snapshot.

All three snapshots (`now` at 17:04:06, `unplugged` at 17:04:24, `replugged`
at 17:04:50) are **identical** on every port/power-supply field:
`power_operation_mode=default`, no partner directory on either port,
`qcom-battmgr-ac`/`-usb` `ONLINE=0`, both `ucsi-source-psy-*`
`ONLINE=0`/`USB_TYPE=[C]` (unresolved). Even the *baseline* snapshot, taken
with the charger already connected per the owner, shows no detection —
unlike the original kernel `-4` finding, where port1 had a sustained
partner (just no PDOs). `journalctl -k --since "17:03:50" --until
"17:05:00"` — spanning the entire deliberate unplug-then-replug — has
**zero lines**: not one UCSI/typec/pmic_glink kernel message of any kind,
during a window that included two real physical connector events.

The owner separately reported the charger "came up momentarily during the
test" — something was observed (likely on the charger's own indicator, or
a brief on-screen change) that neither the kernel log nor the 10-20 s
settle-and-snapshot timing caught.

**This changes the leading explanation.** The `UCSI_CAP_PDO_DETAILS` gap
above still stands as read (it explains why PDOs never populate *when a
partner is registered*), but it cannot explain total silence: on kernel
`-4`, the same firmware, the same UCSI stack, and (per the DT diff between
`-4`'s full DT and `-5`'s GPU test DT — `git show 6d57a98 --
dts/qcom/mahua-hp-omnibook-5-bf1xxx.dtsi`, no `pmic-glink` node changes at
all) the same `pmic-glink` device tree node, *did* register a partner and
hold that state through several minutes of live inspection. A real,
sustained physical connection should produce at least a partner
registration here too, DT and firmware being unchanged. The most likely
explanation is a **marginal physical connection** on this attempt — a
"momentary" appearance is exactly what a connector that isn't fully seated,
or a cable/port with a bad contact, would produce: a brief UCSI attach that
drops before the driver stack settles into a stable state, too fast to
show up in a snapshot taken 10-20 s later or even in the kernel log if the
bounce is filtered/debounced before it reaches a loggable event.

This is not confirmed — it is the best-fit explanation for two different
results (sustained-but-PDO-less on `-4`, versus zero detection on `-5`)
that share identical DT and firmware. It has not been shown that charging
would work correctly if the connection were stable.

## Third attempt: reseated cable, other port, same result

`gpu-test-20260929T171413.txt` (`captures/2026-09-29-gpu-bringup-run1/`): the
owner reseated the cable and used the other physical port, then repeated
the full unplug/replug sequence (`now` 17:14:13, `unplugged` 17:14:29,
`replugged` 17:14:55, plugged in throughout except the deliberate 16 s
gap). **Identical to the second attempt**: `power_operation_mode=default`
and no partner on both typec ports at every snapshot, every power supply
`ONLINE=0`, and `journalctl -k --since "17:14:00" --until "17:15:00"` again
has no UCSI/typec/pmic_glink lines at all.

**This weakens the marginal-connection theory.** A reseated cable on a
different port should rule out one bad contact point; getting the same
flat result twice in a row, on two different physical ports, points more
toward something that changed between kernel `-4` and `-5` than toward
connector wear. Two things are still unverified, though, and matter before
concluding it's a kernel regression:

- **Which physical port maps to which typec node was never established.**
  Only `port1` ever showed a partner (once, on `-4`). If "the other port"
  this time was actually the port that maps to `port0` — which has *never*
  once shown a partner, on any boot — this result says nothing new; it
  would just be testing an already-different, still-unconfirmed port.
- **No same-session A/B test exists.** Every `-4` and `-5` observation so
  far comes from separate boots, so a kernel difference and a connection
  difference (a charger that intermittently makes a good contact) remain
  confounded. The decisive test is the same charger, same port, same
  cable orientation, on kernel `-4` right after a `-5` failure — a real A/B,
  not sequential attempts hours apart.

## The owner's report: the charging LED did light once, briefly

After reviewing the logs above, the owner reported that during one of the
kernel `-5` `--charging` tests, on the port close to the hinge, the
charging LED **did** come on during the replug half of the sequence — real
hardware evidence of a charging attempt starting — but a subsequent
unplug/replug on the same session showed no charging. This does not
contradict the flat snapshots above: the script's replug snapshot is taken
20 s after the owner presses Enter (already after plugging in), so a
charging session that started and then dropped out within that window
would be invisible to a single delayed sample. It also does not resolve
which of the two completed attempts this was, since the physical
port-to-`port0`/`port1` mapping is still unconfirmed (a gap already noted
above).

**This is the clearest lead yet.** It reframes the problem from "the
connector never detects anything" to "a charging session can start (real
LED, so real VBUS/negotiation activity) but does not persist long enough
for Linux's own polling, or the hardware itself, to hold it" — a drop-out,
not a total absence.

Two further attempts, live and tightly polled (0.5 s resolution, custom
poller, not `check-gpu-test.sh`) for about 60 s each around a fresh
unplug/replug, both stayed **completely flat** for the full window — no
partner, no `ONLINE=1`, no `POWER_NOW` deviation from the ongoing discharge
trend, at any of the ~240 total samples across both runs. Whether the LED
lit during either of these two attempts was not confirmed before this
investigating session ended — that is the single most useful thing to
check first next time, watched together with the sysfs state in real time.

## Kernel `-4` vs `-5`: no charging-path code changed

Checked afterwards against the sources, this rules out the kernel
regression the third attempt pointed toward:

- **Base:** qcom-next `a47c4c5aa..e428097a36d` is six commits: five Shikra
  board device trees (`arch/arm64/boot/dts/qcom/shikra-*`) and one revert
  in `sound/soc/qcom/qdsp6/audioreach.c`.
- **Backports `0003`-`0012`** touch only `drivers/gpu/drm/msm/`,
  `drivers/bluetooth/hci_qca.c` and `drivers/i2c/busses/i2c-qcom-geni.c`.
- **Config:** only `CONFIG_CLK_GLYMUR_GPUCC=y` was added.
- **Device tree:** the `pmic-glink` node, ADSP and firmware names are the
  same (above). The GPU test DT adds the GPU block and
  `arm,no-completion-irq` on `/firmware/scmi`.

`drivers/usb/typec/`, `drivers/soc/qcom/pmic_glink*`,
`drivers/power/supply/qcom_battmgr.c` and `drivers/remoteproc/` are
byte-identical between `-4` and `-5`. The difference between the `-4`
partner and the `-5` silence is not kernel code. That leaves the physical
connection or charger state, the GPU-test-only DT additions (unlikely), or
the charger/PMIC state carried over from before Linux started.

Note also that "device tree (full)" follows `/boot/vmlinuz-glymur`, which
is `-5` since the `-5` install, not `-4`. The same-kernel A/B is therefore
"device tree (full)" against "device tree (GPU test)" on `-5`, with the
same charger, cable and port.

## Re-reading the `-4` captures: it did charge

`captures/2026-09-29-usb-c-charging/` holds the `-4` session's files.
`lsmod.txt` has no `scmi_cpufreq`, which was only ever loaded on the `-5`
GPU test boot, and `typec-sysfs.txt` has the port1 PD partner that only
`-4` showed. In `power-supplies.txt` the laptop **is charging**:

| Supply | State in `power-supplies.txt` |
|---|---|
| `qcom-battmgr-bat` | `STATUS=Charging`, `POWER_NOW=40448000` (+40.4 W), `CAPACITY=66`, `ENERGY_NOW=39.66 Wh` |
| `ucsi-source-psy-pmic_glink.ucsi.02` | `ONLINE=1`, `USB_TYPE=C [PD] PD_PPS`, `CURRENT_NOW=3250000` (3.25 A), `CHARGE_TYPE=Standard` |
| `ucsi-source-psy-pmic_glink.ucsi.01` | `ONLINE=0` |
| `qcom-battmgr-ac`, `qcom-battmgr-usb` | `ONLINE=0` |

That snapshot is self-consistent: port1 PD partner, connector 2 online in
PD, 3.25 A in, battery charging at 40 W. The `-8.6 W` discharge and
`ONLINE=0` readings quoted at the top were taken at another moment of the
same session. The internal contradiction the correction note flagged is
therefore two moments, not one broken state. The `-5` GPU test boot at
17:04 found the battery at 53 % (31.98 Wh), so it had been discharging
since this snapshot.

Two conclusions:

- **Charging works on the device-tree boot**, at least sometimes: HP's
  ADSP firmware, PMIC GLink and UCSI all did their part on `-4`. The
  fault is intermittent, not missing support.
- **`qcom-battmgr-ac`/`-usb` `ONLINE` do not track the charger here.**
  Both read 0 while the battery took 40 W. Use the battery's `STATUS` and
  `POWER_NOW` and the UCSI supplies' `ONLINE` instead. The earlier "What
  stands" line at the top of this document relied on them.

On `-4`, the charger was seen as a PD partner before charging began. The
`-5` boot never showed a partner at all, over roughly 15 minutes and five
replugs. The difference is at the UCSI level, and the next test has to
show whether the firmware saw those replugs and Linux missed the
notification, or the firmware never saw them. `glymur-ssd/charging-watch.sh`
records exactly that:

- the connector status asked directly from the firmware every 2 s (UCSI
  debugfs, read-only `GET_CONNECTOR_STATUS`);
- the UCSI tracepoints (every command and connector-change event);
- dynamic debug for `ucsi_glink`, `typec_ucsi`, `pmic_glink` and
  `qcom_battmgr`;
- every sysfs state change, with timestamped notes typed by the person at
  the laptop ("LED on").

## Next

- **Run `sudo bash charging-watch.sh`** on a device-tree boot, then plug,
  unplug and replug, typing a note at each step and whenever the LED
  changes. Leave it running for several minutes after a replug, since
  charging on `-4` started some time after the PD contract.
- **Watch the LED and the sysfs state together, live**, on the next
  attempt: if the LED lights but sysfs never shows a partner even at 0.5 s
  resolution, the drop-out happens deep in firmware/hardware, before UCSI
  ever surfaces it to Linux — a firmware/PMIC question, not a kernel one.
  If sysfs does catch a brief `power_operation_mode=usb_power_delivery` or
  `ONLINE=1` blink, that pins down the actual duration of the session and
  gives something concrete to search the driver for.
- **The A/B test** (revised; see the section above): boot "device tree
  (full)" (`-5`, GPU off) with the same charger, cable and port, and check
  `/sys/class/typec/port*` straight away. A kernel-version bisect is not
  needed, because no charging-path code differs between `-4` and `-5`.
- Identify which physical port is `port0` and which is `port1` (unplug one
  at a time and watch `/sys/class/typec/port*/port*-partner` appear/
  disappear) so future tests aren't ambiguous about which port was used.
- Check charging under the ACPI boot ("Ubuntu on SSD: ACPI, newest glymur
  kernel") with the same charger, to see whether the gap is DT-path-
  specific or universal to this firmware.
- If a stable connection is confirmed on some boot and PDOs still never
  populate, that remaining gap is worth a note to HP/Qualcomm (or an
  upstream `ucsi_glink` quirk request) rather than something fixable from
  this repository.
- No DT or kernel change is proposed here; this is a diagnostic finding
  only.

## `charging-watch.sh`, first live run: connector-change events fire, but never latch "connected"

Ran on "device tree (GPU and USB-A test)" (kernel `-5`), ~7 minutes,
`captures/2026-09-29-usb-c-charging/charging-watch-221357.txt`. This is the
first run to also poll the firmware's own connector status directly (UCSI
debugfs `GET_CONNECTOR_STATUS`, independent of Linux notifications) and
capture the UCSI tracepoints, not just sysfs.

**It started already mid-charge.** The owner plugged the charger in about
a minute before launching the script, in this same boot. By the time the
script started, port1 already had a PD partner and `ucsi-source-
psy-USB0C000:02` at `on=1, PD, 3250000 A`; the first heartbeat reads
`bat_power_uW=40951000` (41 W) — the same order of magnitude as the `-4`
capture caught earlier, established well within that one minute. It
disconnected on its own about a minute into the script's run
(`STATE ... port1:default ... bat=Discharging`), with a
`pmic_glink_altmode: notification on undefined port 1` logged at the same
moment. **The very next heartbeat, 2 s later, still read `+45658000`
(45.6 W, positive/charging) even though `STATE` already said
`Discharging`** — a direct, independent hint of another brief reconnect
too short for the 0.5 s `STATE` loop to catch, caught only because the
heartbeat happened to land inside it.

**Then, for the next ~5.5 minutes, the owner plugged and unplugged both
ports repeatedly ("connected near hinge, no charging yet", "away from the
hinge... nothing", "no leds too") — and both `STATE` (sysfs) and `FW` (the
direct firmware poll) stayed completely flat at disconnected the whole
time.** No sysfs event, no LED, and — new this run — no change in what the
firmware itself reports when asked directly, bypassing any Linux
notification path entirely. That rules out "Linux missed a notification"
as the explanation for this stretch: the firmware's own live answer to
"what's connected right now" was consistently "nothing," for over five
minutes of physical plug/unplug on both ports.

**But two real hardware connector-change interrupts fired anyway, one per
port, each already resolved back to disconnected by the time it was
read:**

```
22:18:33 ucsi_connector_change: port1 status: change=5804, connected=0, ...
22:19:33 ucsi_connector_change: port0 status: change=5804, connected=0, ...
```

Both carry the identical `change=5804` bitmask. These are genuine
firmware-raised UCSI change notifications — not polling, not a Linux
timeout — so something real happened electrically on each port. By the
time the handler read the connector status in response, it had already
reverted to disconnected: the same "resolves faster than anything can
observe `connected=1`" shape as the 45.6 W heartbeat artifact above, and
the same shape as the owner's earlier report of the charging LED lighting
once and then not again.

**Reading this together with the `-4` capture:** the laptop clearly *can*
hold a real PD charging session (41 W, established within about a minute
of plugging in and holding for roughly another minute before dropping) —
this is not a dead port or a fundamentally broken negotiation.
What's inconsistent is whether a given plug event latches into one of
those sessions or collapses back out within under a second, seemingly on
either port. Two independent instruments (a raw power reading and a raw
UCSI interrupt) each caught a sub-2-second-resolution glimpse of that
collapse happening. This looks like a negotiation-stability problem on
this firmware/PMIC path, not a missing driver feature — nothing here
points at a kernel or DT fix.

**Next**, sharper than before: `change=5804` is worth decoding fully
against the UCSI spec's `CONNECTOR_STATUS_CHANGE` bit layout, to see
exactly which fields the firmware says changed on each blip (power-
direction, power-operation-mode, connect-change, etc. are separate bits).
If a future run can catch `connected=1` in the same tracepoint even once,
that pins down how far the negotiation actually gets before collapsing.

## Re-timing that run, and the unacknowledged port notification

A second pass over `charging-watch-221357.txt` changes the reading above.

**The trace lines are late.** `TRACE` lines are timestamped when
`trace_pipe` delivered them, not when they happened. Their kernel times
advance 151 s over 398 s of log time, and the run ended with events still
unread. The `KERN` line fixes the clock: `[610.379567]` was logged at
22:14:55.67. Mapped that way:

| Kernel time | Wall time | Event |
|---|---|---|
| — | 22:14:36 | Owner: charging, LED on, port **away from** the hinge (UCSI connector 2, typec `port1`) |
| — | 22:14:55.39 | `STATE`/`FW`: connector 2 disconnected; battery discharging |
| 610.380 | 22:14:55.67 | `pmic_glink_altmode: notification on undefined port 1` |
| 610.393 | 22:14:55.68 | `ucsi_connector_change: port1 change=5804 connected=0` |
| — | 22:15:10 | Owner: "connected to port near hinge, no charging yet" |
| 635.604 | ≈22:15:20.9 | `ucsi_connector_change: port0 change=5804 connected=0` |
| — | 22:15:38 to 22:20:39 | Owner: more replugs on both ports, no charging, no LED. `FW` stays at "not connected" on both connectors |

`change=5804` is connect change (bit 14), power direction change (12),
partner change (11) and power operation mode change (2)
(`drivers/usb/typec/ucsi/ucsi.h`). With `connected=0` it is a full detach
report.

So the port1 event is the 22:14:55 disconnect itself, not a blip minutes
later. The owner's next note, moving the cable to the hinge port, suggests
that disconnect was the unplug, not a spontaneous drop. The port0 event is
the only trace of the hinge-port plug: a detach report about 10 s later,
with no attach ever read. Trace coverage ends at kernel 706 (22:16:31);
after that only the 2-s `FW` poll covers the run.

The `+45.6 W` heartbeat at 22:14:57 came 2 s after the firmware's own
connector status read "not connected". That is most likely the battery
monitor's cached power value, not a hidden reconnect.

**The lead: the firmware's port notification is never acknowledged.**

- `pmic_glink_altmode` asks the firmware for port notifications
  (`ALTMODE_PAN_EN`) when it starts.
- It acknowledges each one (`ALTMODE_PAN_ACK`) only at the end of the
  worker of a port that has a connector node
  (`drivers/soc/qcom/pmic_glink_altmode.c`, `pmic_glink_altmode_worker`).
- For any other port it logs "notification on undefined port" at debug
  level and returns without acknowledging.
- Our `pmic-glink` node has no connector children, so no notification has
  ever been acknowledged. The message only appeared here because
  `charging-watch.sh` switched on dynamic debug.

The firmware sent a notification for connector 2 at the disconnect. From
then on its own connector status never showed a connection on either
port, through five minutes of replugging.

The `-4` capture fits the same shape: the session charged, then later
attempts failed. That is consistent with the first connection being made
before any notification was left pending. It is not proven: the capture
cannot show whether the firmware waits for the acknowledgement.

**Fix staged (device tree only).** The "device tree (GPU and USB-A test)"
DTB now declares `connector@0` and `connector@1` under `pmic-glink` as
bare `usb-c-connector` nodes: `reg`, dual power and data roles, and no
graph.

- With no graph, `fwnode_typec_mux_get`, `_switch_get` and
  `_retimer_get` return `NULL`, and the `typec_*_set` calls accept that.
- Both ports become defined, so every notification is handled and
  acknowledged.
- `ucsi_glink` also parses these children; its orientation GPIOs are
  optional.

No PHY, repeater or rail is declared. The new DTB is on the USB as
`glymur-tools/usb-test/mahua-hp-omnibook-5-bf1xxx-usb.dtb` (SHA-256
`398b335e…6543`); `grub.cfg` is unchanged.

**Next test** (one boot of the same entry):

1. Run `sudo bash ~/charging-watch.sh` and plug the charger into either
   port.
2. Unplug it, then plug it into the other port, typing notes as before.
3. Check the watch log: its `KERN` lines should no longer contain
   "notification on undefined port". That is a debug message, visible only
   while the script has dynamic debug on.

If the firmware's connector status follows every plug and unplug, the
missing acknowledgement was the cause.

## `charging-watch.sh` bug, September 30: an orphaned trace reader spams hung-task warnings

Confirmed the fix worked (`docs/usb-c-ports-2026-09-29.md`), but the
script's own `charging-watch-20260930T111637.txt` session left processes
running after it ended. Found live, still running, on the next boot:

```
root  17961  1  cat /sys/kernel/tracing/trace_pipe
root  17963  1  journalctl -k -f -n 0 --no-pager -o short-monotonic
root  17964  1  bash /home/rahul/charging-watch.sh   (the "TRACE" while-read loop, state D)
root  17965  1  bash /home/rahul/charging-watch.sh   (the "KERN" while-read loop)
```

All four have `ppid=1`: their original script invocation is gone, so the
`trap cleanup EXIT` that's supposed to `kill $(jobs -p)` never ran against
them — whatever ended the script (closing the terminal, a signal stronger
than the trap catches) didn't take its background readers with it. `cat
trace_pipe`'s blocking read never returns on its own once nothing is
producing new events, so it and its paired `while read` loop wait forever.
The kernel's hung-task detector then logs a growing warning every ~2
minutes indefinitely (`captures/2026-09-30-charging-watch-hang/
hung-task-20260930T112000.txt`, five occurrences by the time this was
caught, `INFO: task bash:17964 blocked for more than 122/245/368/491/614
seconds`) — printed straight to the console at `loglevel=4`, which is what
showed up as stray lines at the bottom of the owner's terminal.

**Not data loss or corruption** — the earlier charging-watch capture and
its findings are unaffected; this is purely a leftover process. Killed
with `sudo kill -9 17961 17963 17964 17965` (find current PIDs with
`ps -ef | grep -E 'charging-watch|trace_pipe|journalctl -k -f'` if this
recurs; the exact numbers change between runs).

**Cause, for next time `charging-watch.sh` is touched:** the `trap cleanup
EXIT` relies on bash actually delivering EXIT to the script's own process
for its background jobs to be reachable via `jobs -p`. That's fragile
against whatever killed this session. A more robust version would track
the backgrounded PIDs explicitly (`$!` right after each `&`) and `kill -9`
them by number in cleanup, and/or close the tracing pipe's read end
directly (`exec {fd}</dev/null` redirection trick, or just always
`kill -9` rather than the default `kill`) so a stuck blocking read can't
survive the trap. Not fixed in this pass; flagging for the next time this
script is edited.

### Correction and fix (September 30, later)

The captured log shows the cleanup trap **did** run: `charging-watch.sh`
disabled the UCSI tracepoints, and the orphaned `journalctl` kept writing
hung-task reports into the same log file after the owner's last note. The
bug was in what the trap killed. `kill $(jobs -p)` signals the `( ... ) &`
subshell of each background reader, not the `cat` and `while read`
processes inside it. Those were reparented to init (`ppid=1`, all four in
the listing are the pipeline members). The `bash` in state D was blocked
on the pipe's mutex (`anon_pipe_read` → `mutex_lock`), held by `cat`,
whose `splice()` from `trace_pipe` holds that lock while it sleeps
waiting for trace events. That wait never ends once tracing is off, and a
mutex wait cannot be interrupted, which is why it tripped the hung-task
detector.

Fixed in `charging-watch.sh`:
- the trace reader is a `while read` loop reading `trace_pipe` directly:
  no `cat`, no pipe, no pipe lock;
- job control is on, so each reader is its own process group, and cleanup
  kills the groups;
- HUP, INT and TERM run the cleanup too;
- a watchdog kills the groups if the script dies without running its
  trap.
