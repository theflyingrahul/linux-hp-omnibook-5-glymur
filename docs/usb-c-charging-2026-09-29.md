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

## Next

- Check charging under the ACPI boot ("Ubuntu on SSD: ACPI, newest glymur
  kernel") with the same charger, to see whether the gap is DT-path-
  specific or universal to this firmware.
- If it is universal, this is worth a note to HP/Qualcomm (or an upstream
  `ucsi_glink` quirk request) rather than something fixable from this
  repository.
- No DT or kernel change is proposed here; this is a diagnostic finding
  only.
