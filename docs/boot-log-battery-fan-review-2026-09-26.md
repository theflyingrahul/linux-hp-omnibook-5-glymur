# Boot Log Review, Battery Path and Fan: September 26, 2026

This covers the workstation boot with the `_OSC` override, stock Ubuntu
`7.0.0-30-generic`, no DTB. The full dmesg and journal are private in
`.work/boot-osc-fix-20260926/`.

## Boot log: errors and warnings by cause

| Message | Count | Cause | Action |
|---|---|---|---|
| `\_SB._OSC` `AE_AML_BUFFER_LIMIT` | gone | HP AML bug | Fixed by the BIOS-gated override (stopgap) |
| `_PSL evaluation failure` (TZn) | 21 | Thermal zones list non-CPU devices (`PEP0`, `GPU0`, `WLTM`, `PMBM`, `CSW0`) as passive devices; Linux expects processors | Passive ACPI cooling does not bind; the EC still controls the fan |
| `AE_NOT_FOUND ... \_SB_.PMBM` | 7 | `PMBM` is referenced in those lists but not defined in this BIOS | Firmware bug; harmless |
| `SYSM.CLSn._LPI: Missing expected return value` | 15 | Cluster idle states are gated by `\_SB.PEPI`, set only by Windows' PEP `_DSM` | Cluster idle belongs to the DT path |
| `acpi-ged ACPI0013:00/01 unable to parse IRQ resource` | 2 | `ECGE` (EC events, PDC pin 768) and `LIGE` (lid, pin 960) use `GpioInt`; Linux `evged.c` accepts only `Interrupt` | Upstream fix: GpioInt support in `evged.c` |
| `CMPS._PSR` / `No handler for Region [ROP1]` | 3 | AC state needs the ABD bridge to PMIC GLink on the ADSP | See the battery section |
| `arm-smmu-v3.2: request_irq(152/153) -EINVAL`, `genirq: Setting trigger mode 1 ... failed` | 4 | IORT gives SMMUv3 event/gerror GSIVs as edge; the GIC rejects that trigger | The SMMU works without event reporting; firmware table issue |
| ECAM not reserved; SPCR access width; BERT invalid; `GPU0._CLS` too small | 5 | Cosmetic firmware bugs | None |
| `PCI: OF: of_root node is NULL` | 2 | Normal on an ACPI boot | None |
| `ath12k: failed to get ACPI BDF EXT: -2` | 1 | Optional ACPI board-data extension absent | None |
| `Timed out waiting for dev-tpm0/tpmrm0` | 2 | TPM start method 9, no `MSFT0101` | Known; TPM separate |
| `pd-mapper.service` failed | 1 | Expects DT remoteprocs | DT path |

## Battery and charging

- The battery `CMBD` (`PNP0C0A`) and AC `CMPS` (`ACPI0003`) read everything
  from `\_SB.PMGK` (`QCOM0F8E`, PMIC GLink).
- `PMGK` fields live in `\_SB.ABD.ROP1`, a GenericSerialBus region that
  Windows serves with its ABD bridge.
- `_BST` returns live data only once `PMGK.LKUP` is set, meaning the GLink
  link to the ADSP battery manager is up.
- The ADSP (`QCOM0F84`) depends on `PILC`, `IPC0`, `RPEN`, `SSDD` and
  `ARPC`, Windows' subsystem loader and IPC drivers. On this Linux ACPI boot
  nothing starts the ADSP. There is no remoteproc, no SMEM/IPCC device and
  no GLink, so there is no battery manager to query.
- Linux's supported path is DT: `qcom_q6v5_pas` boots the ADSP with the
  HP-signed firmware, then `pmic_glink` + `qcom_battmgr` (power supply) and
  `ucsi_glink` (USB-C). These modules are already on the live image but
  unbound.
- Upstream precedent: the X1E HP OmniBook X14 DT loads
  `qcom/x1e80100/hp/omnibook-x14/qcadsp8380.mbn`.

## Fan

- `\_SB.FAN1` (`PNP0C0B`) binds `acpi_fan`. `_FST` reads the RPM from the EC
  (command `0xBC` through `HQEX`), so it only works with the IC10 bus up.
  `_FSL` stores a level and sends nothing to the EC: the EC runs the fan on
  its own.
- Load test (all 12 cores busy for 60 s, then 60 s idle; data in
  `.work/fan-load-test-20260926.tsv`): the fan went from 2482 to 4028 RPM as
  the zones rose from about 43 to 59 °C, then ramped down to 2776 RPM
  within 60 s. The EC fan control responds under Linux.
- This differs from the Snapdragon X1E Dell XPS 13 9345, where the EC needs
  OS-reported thermistor values and suspend notifications and, without its
  EC driver, fans "would kick in late ... [and] keep slowly spinning".
- Open question: the idle floor is about 2500 RPM at 43 °C. Whether
  Windows idles lower or stops the fan is unknown.
- DT safety note from the X14: upstream reserves TLMM GPIOs there, including
  the EC's lines. On some Snapdragon laptops, toggling the EC reset GPIO
  prevents power-up until the battery is disconnected. This board's EC
  reset and other EC GPIOs must be identified and reserved before any DT
  boot.
