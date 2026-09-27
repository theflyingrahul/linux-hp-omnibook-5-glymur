# HP OmniBook 5 16-bf1xxx: board layer

Everything specific to this laptop lives here or is referenced from here.
The kernel patches under `patches/kernel/upstream/` and
`patches/kernel/glymur-bringup/` contain mechanisms only; the values below
switch them on for this board.

| Item | Where | Why it is board-specific |
|---|---|---|
| Kernel command line | `kernel-cmdline.conf` | Pins and I²C controllers proven on this machine |
| DSDT `_OSC` override | `scripts/linux/glymur-dsdt-osc-fix.py` (output private, BIOS-gated) | Works around an HP BIOS F.06 AML bug |
| Wi-Fi board data | `scripts/linux/ath12k-board-add.py` (output private) | HP subsystem `103c:8ef3` needs Windows' `bdwlan_qcc2072_1p0_ncm820A.elf` |
| Firmware for ADSP/CDSP/GPU | extracted from the Windows driver store (private) | HP-signed images |

## Kernel command line

`kernel-cmdline.conf` holds the module parameters:

- `glymur_acpi_gpio.enable=1 glymur_acpi_gpio.pins=3,51,66,67,92` enables
  these TLMM pins:

  | GPIO | Use |
  |---:|---|
  | 3 | Touchpad interrupt (PDC pin 896) |
  | 51 | Touchscreen interrupt |
  | 66 | EC events (PDC pin 768) |
  | 67 | Keyboard interrupt (PDC pin 704) |
  | 92 | Lid (PDC pin 960, also the `LIDR` OpRegion) |

- `i2c_qcom_geni.acpi_buses=0xb80000,0xb90000,0xa80000,0xa84000` binds these
  controllers:

  | Controller | Device |
  |---|---|
  | I2C1 | Keyboard `QTEC0001` at 0x3A |
  | I2C5 | Touchpad `ELAN0189` at 0x15 |
  | I2C9 | Touchscreen `ELAN2513` at 0x10 |
  | IC10 | EC at 0x76, over GPI DMA |

  I2C6 (SAR sensors and `QCOM0FC6`) is deliberately left out: it has never
  been read.

- `systemd.tpm2_wait=0`: the firmware publishes an ACPI `TPM2` table, but
  its start method (9) has no Linux driver and no `MSFT0101` device exists.
  systemd's TPM2 generator therefore waits for `/dev/tpm0` and
  `/dev/tpmrm0` and times out after 90 s on every boot (live inventory
  journal, 2026-09-26). The parameter stops it waiting. Drop it once a TPM
  driver binds.

Evidence for every value is in `docs/acpi-input-results-run2-2026-09-26.md`,
`docs/cpuidle-and-ec-bus-results-2026-09-26.md`, and
`docs/qcom-next-port-and-lid-2026-09-26.md`.
