# Windows Fan and Thermal Profile, Compared with Linux: September 27, 2026

Run: `scripts/windows/fan-thermal-profile.ps1`, elevated, **on battery**
(recorded `PowerOnline = False` in every sample; Balanced plan; about 56 %
charge afterwards), with the machine otherwise idle. The Linux run it is
compared with was also on battery. Protocol: 60 s idle, 60 s with all 12 CPUs busy,
120 s recovery, sampled every 5 s. Raw data is private in
`.work/windows-fan-profile-20260927T143355.tsv`.

## What Windows exposes

- **No fan speed.** HP's `HPBIOS_BIOSNumericSensor` class returns no
  sensors on this BIOS, `Win32_Fan` has no instances, and the fan is only a
  generic "ACPI Fan" (`PNP0C0B`) device with no counters. The RPM
  comparison therefore needs Linux, where `acpi_fan` reads `_FST` from the
  EC.
- **Two kinds of thermal zones.**
    - `TZ31` to `TZ34` are ACPI zones named "EC thermistor 1" to "EC
      thermistor 4". They are the four `acpitz` zones Linux reads over the
      EC bus, so they are the like-for-like comparison.
    - `TZ0`, `TZ1`, `TZ99` and the other SoC zones have no `_TMP` in the
      DSDT. Windows fills them from Qualcomm sensor drivers
      (`QCOM0F58`, `QCOM0F59`, `QCOM0F5A` and others). Linux under ACPI
      cannot read them.
- **Energy meter** rails (`cpu_cluster_0/1`, `soc`, `gpu`, `memory`,
  `system` and others), a platform power meter, and per-zone
  `% Passive Limit` and `Throttle Reasons`. The script now records all of
  them. They were not in this run.

## Results (Windows)

| Zone | Idle | Load peak | End of recovery |
|---|---|---|---|
| TZ31 (EC thermistor 1) | 38–39 °C | 51 °C | 41 °C |
| TZ32 (EC thermistor 2) | 39–40 °C | 57 °C | 42 °C |
| TZ33 (EC thermistor 3) | 40 °C | 50 °C | 43 °C |
| TZ34 (EC thermistor 4) | 35–37 °C | 38 °C | 37 °C |
| TZ1 (SoC, Windows only) | 38–39 °C | 86 °C (WMI 86.7) | 40 °C |

- **Idle CPU:** about 355 MHz, with `% Processor Performance` near 10.
- **Load:**
    - The frequency counter reads 3350 MHz and performance is 90 %.
    - After about 26 s, when the SoC zones reached about 86 °C, performance
      fell to about 63 % and stayed there. `TZ1` then settled near 60 °C.
    - On battery this can be either a thermal passive limit or the
      battery power policy (a short boost, then a lower sustained limit).
      The temperatures falling while the load continued point to the
      power limit, but this run did not record `% Passive Limit`. The
      extended script does.
    - A separate 5 s load sample (also on battery) drew about 28.5 W on the SoC (21.4 W on
      one CPU cluster) and 45 W for the system. The idle platform draws
      about 4.4 W, 0.42 W of it the SoC; the battery reported a 3.7 W
      discharge rate at idle.
- The skin-side EC thermistors peaked at no more than 57 °C.

## Comparison with Linux (stock Ubuntu 7.0, 2026-09-26)

| | Linux | Windows |
|---|---|---|
| EC thermistors, idle | about 43 °C | 35–40 °C |
| EC thermistors, all-core load peak | about 59 °C | 38–57 °C |
| Fan | 2482 → 4028 → 2776 RPM | not exposed |
| CPU frequency | fixed at the firmware's clock (no `_CPC`/`_PSS`) | 355 MHz idle, 3350 MHz load, limited after about 26 s (battery) |
| CPU idle | core C1/C4 with the `_OSC` fix; no cluster states | full PEP-managed idle |

- **Linux idles 3–8 °C warmer** on the same EC thermistors. The likely
  cause is that Linux can neither lower the clock (Windows idles at
  355 MHz) nor enter cluster idle states. It is not a fan-control problem:
  the EC runs the fan itself on both systems.
- **Under load the peaks are similar** (about 59 °C against 57 °C), so the
  EC fan curve keeps the skin side in range under Linux too. The SoC zones
  that trigger Windows' throttling are invisible to Linux under ACPI.
  Qualcomm's limits hardware (LMh) and TSENS thermal shutdown still
  protect the SoC independently of the OS.
- **The idle fan floor is still an open question:** Linux ran about
  2500 RPM at 43 °C, and Windows reports no RPM. Whether the fan is
  audible at idle under Windows can only be checked by ear.
- These zones are identified by ACPI path from now on: the Linux profiler
  now labels each `acpitz` zone with it (`\_SB_.TZ31`).

## Results (Linux, qcom-next boot kernel, SSD install, 2026-09-27)

Run: `scripts/linux/fan-thermal-profile.sh`, on battery, same protocol (60 s
idle, 60 s all-core load, 120 s recovery, 5 s interval). Raw data is private
in `.work/linux-fan-profile-20260927T141943.tsv`. Full first-boot context
(what else was working) is in `docs/qcom-next-first-boot-2026-09-27.md`.

| Zone | Idle | Load peak | End of recovery |
|---|---|---|---|
| TZ31 (EC thermistor 1) | 42.8 °C | 53.8 °C | 44.8 °C |
| TZ32 (EC thermistor 2) | 43.8 °C | 62.8 °C | 46.8 °C |
| TZ33 (EC thermistor 3) | 43.8 °C | 56.8 °C | 46.8 °C |
| TZ34 (EC thermistor 4) | 40.8 °C | 40.8 °C | 40.8 °C |
| Fan | 2501–2546 RPM | 4408 RPM (still rising into recovery, peak 4428 at t=129s) | 2800 RPM (not back to the idle floor within 120 s) |

CPU frequency scaling and cluster idle are still absent (no `_CPC` table),
unchanged from the stock-Ubuntu run.

## Three-way comparison (stock Ubuntu 7.0 vs qcom-next SSD boot, both Linux, both battery; Windows for reference)

| | Linux (stock 7.0, 09-26) | Linux (qcom-next, SSD, 09-27) | Windows |
|---|---|---|---|
| EC thermistors, idle | about 43 °C | 40.8–43.8 °C | 35–40 °C |
| EC thermistors, load peak | about 59 °C | 40.8–62.8 °C | 38–57 °C |
| Fan | 2482 → 4028 → 2776 RPM | 2501–2546 → 4408 → 2800 RPM | not exposed |
| CPU frequency | fixed (no `_CPC`/`_PSS`) | fixed (no `_CPC`/`_PSS`) | 355 MHz idle, 3350 MHz load |
| CPU idle | core C1/C4, `_OSC` fix | `LPI-0`/`LPI-1` in use | full PEP-managed idle |

The qcom-next boot kernel tracks the stock-Ubuntu run closely on EC
thermal/fan behavior — same EC driver path, same firmware fan curve — with a
slightly higher load peak (TZ32 62.8 °C vs 59 °C reported previously) and a
correspondingly higher fan ceiling (4408 vs 4028 RPM). Neither run's fan
returned to its idle floor within the 120 s recovery window. CPU frequency
scaling and cluster idle gaps are unchanged; both still need the
device-tree path.

## Next

- Optionally repeat the Windows run with the extended script, once on
  battery and once on AC, to separate the thermal passive limit from the
  battery power policy. Keep the Linux runs on the same power source; Linux
  cannot read the AC state yet (PMIC GLink), so note it by hand.
- Real parity needs CPU DVFS and cluster idle, which means the DT path
  (`cpufreq-hw`, RPMh, PSCI OSI).
