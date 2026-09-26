# Hardware Topology

This document describes the physical architecture of the HP OmniBook 5 16-bf1xxx family based on the HP Maintenance and Service Guide (P39932-002) and User Guide (P39931-002).

## System Board
- **HP-DOCUMENTED**: Qualcomm Snapdragon X2 Elite X2E-84-100 processor option exists with 32 GB LPDDR5X-8448 dual-channel onboard memory (Service part number: Q02174-601).
- **OBSERVED-HARDWARE**: Windows reports the Snapdragon X2 Elite X2E84100 configuration with approximately 32 GB RAM.

## Display Assembly
- **HP-DOCUMENTED**: 16.0 inch WUXGA (1920 × 1200) OLED, low blue light, bent panel, BrightView, DCI-P3 95%, eDP 1.2 without PSR, 300 nits, 60 Hz, DBTS (Touch).
- **HP-DOCUMENTED**: Display uses a specific display panel cable with a 4-pin connector at the bottom of the OLED panel.
- **HP-DOCUMENTED**: 16-inch OLED touchscreen.

## Camera
- **HP-DOCUMENTED**: HP True Vision FHD Camera (USB2 based), with indicator LED, 1x infrared (IR) LED, f2.0, HD BSI sensor, WDR/TNR, 80° NFOV.
- **OBSERVED-HARDWARE**: HP True Vision FHD and HP IR camera functions are present under USB `VID_30C9&PID_00D9`.

## WLAN Module
- **ACPI-DESCRIBED**: The decompiled DSDT describes the segment-4 PCI host bridge as `PCI4` with `_UID`/`_SEG` 4 and a generic child endpoint at `_ADR` zero. Mainline `pcie4` declares Linux PCI domain 4, narrowing the WLAN host candidate; reset/wake GPIOs, PHY, regulators, and lane wiring remain UNKNOWN.
- **HP-DOCUMENTED**: Removable M.2 2230 slot.
- **HP-DOCUMENTED**: Options include Qualcomm Wi-Fi 7 FastConnect C7700 + Bluetooth 6.0 (P59089-005) or Qualcomm FastConnect 6900 Wi-Fi 6E + Bluetooth 5.3 WW WLAN (P13807-005).
- **OBSERVED-HARDWARE**: Windows reports a Qualcomm FastConnect C7700 NCM820A Wi-Fi 7 adapter and its Bluetooth function. The WLAN function is at PCI segment 4, bus 1, device 0, function 0, behind a segment-4 root port and ACPI host bridge `PNP0A08\4`; the mainline domain match supports `pcie4`, but Linux resources and functionality remain UNKNOWN.

## Input Devices
- **ACPI-DESCRIBED**: The DSDT places `TSC1` / `ELAN2513` at I²C address `0x10` on `I2C9` and `TCPD` / `ELAN0189` or `ELAN0143` at address `0x15` on `I2C5`. Their `_STR` values and resource bases map the controllers to mainline `i2c8` (`0xA80000`) and `i2c4` (`0xB90000`) respectively. GPIO interrupt translation, Linux driver binding, and functionality remain unverified.
- **HP-DOCUMENTED**: Keyboard daughterboard is present (Part P48630-601 for X2 Plus/Elite processor units).
- **HP-DOCUMENTED**: Touchpad is a Precision Clickpad with an image sensor.
- **OBSERVED-HARDWARE**: Windows reports ELAN touchscreen and touchpad functions, including `HID\VEN_ELAN&DEV_2513` and `ACPI\ELAN0189`.

## Storage
- **ACPI-DESCRIBED**: The decompiled DSDT describes the segment-5 PCI host bridge as `PCI5` with `_UID`/`_SEG` 5 and an explicit `NVME` child at `_ADR` zero. Mainline `pcie5` declares Linux PCI domain 5 (`pcie3b` declares 7), narrowing the NVMe host candidate; reset/wake GPIOs, PHY, regulators, and lane wiring remain UNKNOWN.
- **HP-DOCUMENTED**: M.2 2280 PCIe NVMe.
- **OBSERVED-HARDWARE**: Windows reports a Samsung NVMe controller at PCI segment 5, bus 1, device 0, function 0, behind a segment-5 root port and ACPI host bridge `PNP0A08\5`; the Linux domain match supports `pcie5`, but Linux resources and functionality remain UNKNOWN.

## Auxiliary Boards
- **HP-DOCUMENTED**: USB/audio board connected via dedicated cable.

## USB-C / UCSI
- **ACPI-DESCRIBED**: The DSDT exposes a `USBC000` UCSI device with three connector child nodes. The photographs show two external USB Type-C receptacles plus one USB Type-A receptacle, so ACPI connector-to-physical-port mapping remains unresolved; Linux USB-C, Power Delivery, and DisplayPort Alt Mode behavior remain untested.

## Battery
- **HP-DOCUMENTED**: 3-cell 59 Wh battery.

## Physical Port and Firmware Evidence
- **OBSERVED-HARDWARE**: Private photographs show two USB Type-C ports on one side and one USB Type-A port plus a 3.5 mm audio jack on the opposite side.
- **OBSERVED-UEFI**: BIOS Main identifies `HP OmniBook 5 Laptop 16-bf1xxx`, product number `D3ZN3UA#ABA`, board ID `8F47`, BIOS `F.06`, Snapdragon X2 Elite X2E84100, and 32 GB memory.
- **OBSERVED-UEFI**: BIOS Configuration records fan-always-on disabled, USB charging enabled, Adaptive Battery Optimizer enabled, 30-second keyboard-backlight timeout, and power-on-when-lid-opens enabled. These settings do not establish Linux device-tree properties.
