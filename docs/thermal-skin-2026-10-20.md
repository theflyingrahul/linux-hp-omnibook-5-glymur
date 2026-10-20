# Thermal: HP's Skin-Temperature Limits, October 20, 2026

Issue #16. Read-only comparison of HP's ACPI thermal zones (DSDT, BIOS
F.06) with the device tree; the test runs on the next boot.

## HP's thermal policy

HP's DSDT has 39 thermal zones in two layers (modem and Glymur-only zones
left out):

| Zone | What | Passive | Hot | Critical | Throttles |
|---|---|---|---|---|---|
| `TZ0`, `TZ1` | CPU clusters 0 and 1 (`QCOM0F58/59`) | 105 °C | | | CPUs (through the PEP) |
| `TZ6` | GPU (`QCOM0F91`) | 95 °C | | | GPU |
| `TZ11` | NSP (`QCOM0FB5`) | 105 °C | | | NSP |
| `TZ99` | all internal TSENS sensors (`QCOM0F5A`) | 110 °C | 100 °C | 115 °C | everything |
| `TZ31` | EC thermistor 1 | 65 °C | 70 °C | 115 °C | CPUs, GPU, NSP, Wi-Fi |
| `TZ32` | EC thermistor 2 | 58 °C | 85 °C | 90 °C | `PPLD`, Qualcomm's PowerLimits device |
| `TZ33` | EC thermistor 3 | 75 °C | 85 °C | 90 °C | CPUs, GPU, NSP, Wi-Fi |
| `TZ34` | EC thermistor 4 | 50 °C | 80 °C | 85 °C | CPUs, GPU, NSP, Wi-Fi |

The EC thermistor zones are the four "ACPI Thermal Zone" devices Windows
lists; their `_TMP` reads the EC (`IC10._DSM` function 6), the same
readings the HP EC driver reports (`docs/ec-2026-09-30.md`), and their
sampling period (`_TSP`) is 5 s. `TZ35`–`TZ37` are disabled (`_STA` 0).
HP's `_HOT` asks Windows to hibernate.

`PPLD` (`QCOM103F`, "Qualcomm PowerLimits Device", run by Qualcomm's PEP
driver `qcpep_8480` on Windows) caps the SoC's total power. Its `_DSM`
holds a thermal power table, from 45 W at 100 % down to 20 W at 0 % in
eleven steps over 15 s windows, and a table of sustained and burst power
limits (25–27 W over 100 s, with shorter bursts). When `TZ32` passes 58 °C,
Windows walks down that table. Its `_STA` follows a PEP `_DSM` that chooses
between it and Microsoft's own platform thermal devices (`MSFT000x`, gated
by `EMPF`); on this laptop Windows runs `PPLD`.

## The device tree

The SoC layer is already there: `glymur.dtsi` has 69 TSENS zones with
critical trips at 115 °C and the GPU zones with passive trips at 95 °C
mapped to the GPU, as HP's `TZ6` and `TZ99`. The CPU zones carry only
critical trips, as upstream Qualcomm laptops do; CPU throttling runs in
the CPU control processor's firmware.

The skin layer is missing: nothing on Linux acts on the EC thermistors,
so the SoC runs up to its own limits where Windows throttles at 50–75 °C
of skin temperature.

## The change (kernel -15, test device tree)

The upstream pattern is a board thermal zone on a thermistor, with
passive trips mapped to the CPUs, as in the ThinkPad X13s's
`skin-temp-thermal`. An hwmon driver's temperature channels become
thermal sensors through the hwmon core's `HWMON_C_REGISTER_TZ`.

- `upstream/qcom-next/0004`: the EC binding allows `#thermal-sensor-cells`
  (1, the thermistor index).
- `upstream/qcom-next/0005`: the EC driver sets `HWMON_C_REGISTER_TZ`; a
  channel without a thermal zone in the device tree is skipped, so
  nothing changes on the other device trees.
- The test device tree adds `ec-thermistor-1`…`4-thermal` with HP's
  passive and critical trips and 5 s polling (the EC has no working event
  line, #11), mapping the passive trips to all twelve CPUs and the GPU.
  `TZ32`'s passive trip acts only through Qualcomm's PowerLimits device,
  for which Linux has no driver, so that zone keeps only its critical trip.
  See "The power limits on Linux" below. HP's
  hot trips are left out: on Linux they only notify.

A critical trip shuts the laptop down in an orderly way, as Windows does
at `_CRT`. A thermistor the EC cannot read returns an error, not a
temperature, so it cannot trigger one.

## The power limits on Linux

Windows' PowerLimits device and Linux's `qcom_spel` driver program the
same hardware. Qualcomm's PEP driver (`qcpep8480.sys`) names it: its
settings are `PowerLimitsSocPl1`…`Pl4` and `PowerLimitsSystemPl1`…`Pl4`
(value and time window each), per-subsystem CPU/GPU/NPU PL1/PL2 ranges,
`PowerLimitsDisableAtSpel` and EC inputs
(`SPEL_SYS_ACTIVE_CONSTRAINING_LIMITS_EC`). Neither its INF nor the
registry sets values on this laptop, so it runs its defaults and HP's
ACPI tables.

- **Driver:** "powercap: qcom: Add SPEL powercap driver" (Manaf
  Meethalavalappu Pallikunhi, Qualcomm). qcom-next `1a0586064ee1` carries
  v2 (`1e54bea9368e`), and `glymur.dtsi` enables `power-limits@ef3b000`
  (`qcom,glymur-spel`). `qcom_spel` is loaded in every module list saved
  in `captures/` (the `-6` to `-14` boots). v3 (2026-07-02, in the laptops
  kernel) adds a common power-limit-controller binding and fixes
  use-after-free bugs. It is under review, with no v4 public and nothing
  in linux-next.
- **What it exposes:** powercap zones for `sys`, `soc`, `cl0`–`cl2`, `igpu`,
  `dgpu`, `nsp`, `mmcx`, `infra`, `dram`, `mdm`, `wlan` and `usb1`–`3`
  (energy counters). Only `sys` and `soc` have limits: PL1–PL4, each with
  a time window, through `/sys/class/powercap`.
- **What is missing is policy, not a driver.** Windows lowers the SoC limit
  as `TZ32` warms (45 W at 100 % down to 20 W) and applies HP's
  sustained and burst limits (`PLP1`). On Linux, no kernel mechanism ties a
  thermal zone to a powercap limit (the DTPM framework works the other way
  round, budgeting power across devices). The SPEL cover letter leaves it
  to "userspace applications and thermal management daemons". The x86
  counterpart, thermald with Intel RAPL, is Intel-only, and no Qualcomm
  Linux daemon is published.
- **Next:** read the limits the firmware leaves set (the runbook does).
  If they already match HP's sustained limit, only `TZ32`'s ladder is
  missing. That would be a small userspace service writing the `soc` PL1,
  to be weighed against the CPU and GPU throttling the other three zones
  already give.

Not checked yet: `dt_binding_check` on the binding change (dtschema
would not install on the build host).
