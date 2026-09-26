# ACPI Evidence Review — 2026-09-14

This is a curated review of the elevated capture at `.work/day0-capture-20260914-acpi`. The raw tables and generated ASL are ignored working artifacts. The source table manifest passed SHA-256 validation.

## Method

The capture contains the DSDT, three SSDTs, and related platform tables. The colocated ACPICA `iasl.exe` completed a combined disassembly using the SSDTs as external-resolution tables. The generated ASL is inspection material only; it is not treated as compilable source or as a device tree.

## PCIe Evidence

| Windows observation | ACPI evidence | Linux interpretation |
|---|---|---|
| Segment 4, bus 1, device 0, function 0; WLAN | `\_SB.PCI4`, `_HID` `PNP0A08`, `_UID`/`_SEG` 4; `RP1` and generic `EP1` children at `_ADR` zero | Mainline `pcie4` declares `linux,pci-domain = <4>`; domain match narrows the node, but board resources remain unverified |
| Segment 5, bus 1, device 0, function 0; Samsung NVMe | `\_SB.PCI5`, `_HID` `PNP0A08`, `_UID`/`_SEG` 5; `PCI5.RP1.NVME` at `_ADR` zero | Mainline `pcie5` declares domain 5 while `pcie3b` declares domain 7; `pcie5` is the domain match, but board resources remain unverified |

The ACPI segment numbers corroborate the Windows parent paths. Matching mainline `linux,pci-domain` values narrow the PCIe nodes, but do not by themselves establish controller base usage, PHYs, clocks, resets, GPIOs, or power supplies.

The fetched HP reference patches strengthen only part of this comparison: both reference boards place WLAN on `pcie4`, while one places NVMe on `pcie5` and the other on `pcie3b`. Their WLAN nodes use `pci17cb,1107`; this target reports `DEV_1112`, so the reference node must not be copied unchanged.

## I²C-HID and USB-C Evidence

- `TCPD` exposes `ELAN0189` or `ELAN0143` by platform selection, uses the HID-over-I²C compatible ID, and depends on `I2C5` and `GIO0`.
- `TSC1` exposes `ELAN2513`, uses the HID-over-I²C compatible ID, and depends on `I2C9` and `GIO0`.
- `UCSI` exposes `USBC000` with three connector children (`UCN0`–`UCN2`) and a system-memory operation region at `0x81D20000`. This confirms firmware-described UCSI topology, not Linux USB controller or PHY routing.

Windows PnP properties independently associate the two HID devices with BIOS names `\_SB.TCPD` and `\_SB.TSC1`. The ACPI controller `_STR` values and resource bases now establish the controller mapping against `glymur.dtsi`: `I2C5` is `QUP_0_SE_4` at `0xB90000`, matching Linux `i2c4` at `i2c@b90000`; `I2C9` is `QUP_1_SE_0` at `0xA80000`, matching Linux `i2c8` at `i2c@a80000`.

The controller mapping is confirmed, but HID addresses, GPIO numbers/polarities, interrupts, pinctrl states, and target Linux device nodes remain unknown. Do not copy reference-board HID properties from this mapping alone.

## Next Gate

Manual port and BIOS/UEFI evidence is now complete and private originals are preserved. The I²C controller mapping is confirmed; PCIe, USB-C, and board-level power/GPIO mappings still require the same comparison. Record each mapping as confirmed, candidate, or unknown. Only confirmed mappings should enter a target DTS. Reference-board values remain non-authoritative.
