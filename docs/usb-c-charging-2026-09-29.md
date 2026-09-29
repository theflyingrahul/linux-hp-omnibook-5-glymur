# USB-C Charging: Plugged In, Not Charging, September 29, 2026

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
test)" boot (`docs/gpu-bringup-run1-2026-09-29.md`), private logs in
`.work/gpu-bringup-run1-2026-09-29/`:

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

`gpu-test-20260929T171413.txt` (`.work/gpu-bringup-run1-2026-09-29/`): the
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

## Next

- **Watch the LED and the sysfs state together, live**, on the next
  attempt: if the LED lights but sysfs never shows a partner even at 0.5 s
  resolution, the drop-out happens deep in firmware/hardware, before UCSI
  ever surfaces it to Linux — a firmware/PMIC question, not a kernel one.
  If sysfs does catch a brief `power_operation_mode=usb_power_delivery` or
  `ONLINE=1` blink, that pins down the actual duration of the session and
  gives something concrete to search the driver for.
- **The decisive test**: reboot to "Ubuntu on SSD: device tree (full)"
  (kernel `-4`) with the exact same charger, cable, and port just used on
  `-5`, and check `/sys/class/typec/port*` immediately. If a partner
  registers there and not on `-5`, that is a real kernel-version
  regression between `e428097a36d`+backports and the earlier base — worth
  bisecting. If it stays silent on `-4` too, the fault is either the
  charger/cable/port combination itself or something that changed on the
  laptop/charger between the original observation and now (e.g. the
  charger's own state), not a Linux regression.
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
