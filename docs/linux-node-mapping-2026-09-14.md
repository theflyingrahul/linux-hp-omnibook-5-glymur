# Linux Node Mapping — 2026-09-14

This is the first evidence-backed mapping from the target ACPI capture to the pinned September 14 mainline Glymur SoC source. It does not establish a complete target DTS.

## Confirmed controller mappings

| Target ACPI | ACPI evidence | Mainline source | Result |
|---|---|---|---|
| `I2C5` | `_STR` `QUP_0_SE_4`; resource base `0xB90000` | `glymur.dtsi`: `i2c4: i2c@b90000` | Controller confirmed |
| `I2C9` | `_STR` `QUP_1_SE_0`; resource base `0xA80000` | `glymur.dtsi`: `i2c8: i2c@a80000` | Controller confirmed |

## PCIe domain constraints

| Target ACPI | Mainline domain declaration | Result |
|---|---|---|
| `PCI4`, segment 4; WLAN | `pcie4`: `linux,pci-domain = <4>` | Domain match; board resources unresolved |
| `PCI5`, segment 5; NVMe | `pcie5`: domain 5; `pcie3b`: domain 7 | `pcie5` is the domain match; board resources unresolved |

The ACPI HID devices are therefore associated with the mainline controller candidates `i2c4` (`TCPD`, ELAN0189/ELAN0143) and `i2c8` (`TSC1`, ELAN2513). This confirms the controller identity, not the Linux child-node definition. The Ubuntu ACPI capture registered no I²C adapters or HID children, so these mappings are not yet a working Linux implementation.

At the pinned mainline commit, `drivers/i2c/busses/i2c-qcom-geni.c` matches ACPI IDs `QCOM0220` and `QCOM0411`, while the target controllers use `QCOM0F10`. The live capture contains no GENI/I²C probe or adapter registration. The collector did not capture the running kernel's driver configuration or ACPI platform-device list, so the unmatched ID is a source-level gap, not yet a complete diagnosis of that Ubuntu kernel. The driver also expects wrapper and clock resources; adding an ID alone is not a validated fix.

## Still unresolved

- GPIO interrupt translation and polarity, pinctrl states, and reset/wake behavior. The ACPI I²C serial-bus resources already encode `TCPD` address `0x15` on `I2C5` and `TSC1` address `0x10` on `I2C9`; these are firmware descriptions, not yet tested Linux clients.
- PCIe reset/wake GPIOs, PHYs, regulators, lane wiring, and endpoint properties.
- UCSI’s three ACPI connector children versus the two photographed USB Type-C receptacles; do not enable three physical ports from ACPI names alone.
- USB-C PHY, DisplayPort Alt Mode, regulator, panel, audio, and firmware routing.

Use the mainline checkout at commit `704340f1cd0dcef829eb62f5b48ae95a2ce17bdf` for source comparison. Only confirmed properties should enter a target DTS; all reference-board values remain candidates until independently supported.
