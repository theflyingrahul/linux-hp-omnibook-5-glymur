# Day-0 Evidence — 2026-09-14 (Elevated)

This is a curated, redacted summary of the elevated local capture at `.work/day0-capture-20260914-acpi`. The raw capture is ignored and must not be committed. `analyze-day0-capture.py` validated its SHA-256 manifest.

## Capture Scope

- Script version `0.2.0`, schema version `1`.
- Metadata-only pass; driver export and firmware copying were disabled.
- The process was elevated. ACPI registry, BCD/recovery, security, and complete power metadata were captured. ACPICA binary tables were captured with the supplied ACPICA tools.

## Observed Target Facts

- Windows identifies the machine as `HP OmniBook 5 Laptop 16-bf1xxx`, family `103C_5335KV HP OmniBook 5`, with baseboard `8F47`, BIOS `F.06`, and ARM64 Windows. The processor is Snapdragon X2 Elite X2E84100 with approximately 32 GiB RAM.
- PnP identifies `Qualcomm FastConnect C7700 NCM820A Wi-Fi 7 Network Adapter` and its Bluetooth adapter. The observed Wi-Fi instance uses PCI `VEN_17CB&DEV_1112` with subsystem `8EF3103C`; the FriendlyName, not the numeric ID alone, establishes the C7700 label.
- PnP identifies an HP True Vision FHD camera and HP IR camera under `USB\VID_30C9&PID_00D9`.
- ELAN touchscreen/touchpad devices are present, including `HID\VEN_ELAN&DEV_2513` and `ACPI\ELAN0189`.
- Windows places the WLAN function at PCI segment 4, bus 1, device 0, function 0, behind a segment-4 root port and ACPI host bridge `PNP0A08\4`.
- Windows places the Samsung NVMe controller at PCI segment 5, bus 1, device 0, function 0, behind a segment-5 root port and ACPI host bridge `PNP0A08\5`.
- The ACPICA capture includes the DSDT, three SSDTs, and the related platform tables listed under `raw/acpi/tables/`. A combined `iasl -e` pass completed successfully with the supplied SSDTs. The generated ASL is inspection material only and is not a source for recompilation or a DTS.
- The decompiled DSDT describes `\_SB.PCI4` as a PCI Express host bridge with `_UID`/`_SEG` 4 and `\_SB.PCI5` as a PCI Express host bridge with `_UID`/`_SEG` 5. `PCI5.RP1.NVME` is an explicit ACPI child at `_ADR` zero, corroborating the Windows segment-5 NVMe path; the segment-4 bridge has a generic endpoint at the corresponding path, while Windows identifies the function as WLAN.
- ACPI describes the ELAN touchpad path as `TCPD` on `I2C5` with hardware ID `ELAN0189` (or `ELAN0143` by platform selection), and the touchscreen as `TSC1` / `ELAN2513` on `I2C9`. Their controller resources identify `I2C5` as `QUP_0_SE_4` / `0xB90000` (`i2c4`) and `I2C9` as `QUP_1_SE_0` / `0xA80000` (`i2c8`) in mainline Glymur. ACPI also describes a `USBC000` UCSI device with three connector child nodes.
- Two display EDID records were captured; panel identity and routing still need review.

## Manual Physical and UEFI Evidence

Six private photographs were reviewed on 2026-09-14. They show two USB Type-C receptacles on one side, one USB Type-A receptacle and a 3.5 mm audio jack on the opposite side, and the keyboard/touchpad assembly. The chassis remains unopened.

The BIOS Main page shows product name `HP OmniBook 5 Laptop 16-bf1xxx`, system family `HP OmniBook 5`, product number `D3ZN3UA#ABA`, system board ID `8F47`, Snapdragon X2 Elite X2E84100, 32 GB memory, Insyde firmware, and BIOS revision `F.06`. Serial number, UUID, board CT number, battery serial, and other private identifiers were intentionally not transcribed.

The BIOS Configuration page records fan-always-on disabled, USB charging enabled, Adaptive Battery Optimizer enabled, keyboard backlight timeout of 30 seconds, and power-on-when-lid-opens enabled. The Security page shows administrator and power-on passwords clear, TPM clear not selected, and Absolute Persistence inactive. These settings are observational context, not DTS properties.

## Not Yet Established

Linux ACPI boot and several PCIe/USB functions are now established, but no Linux I²C adapter registered, no keyboard/touchpad input appeared, and GPIO numbering, USB-C routing, panel, audio, power, and board-specific DT resources remain unknown. Do not construct a target DTS from these observations alone; see `docs/ubuntu-live-boot-results-2026-09-15.md`.
