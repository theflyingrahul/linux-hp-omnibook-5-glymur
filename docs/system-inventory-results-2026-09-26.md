# Whole-System Live Inventory: September 26, 2026

The HP OmniBook 5 completed the default-off Ubuntu 26.04.1 ARM64 RAM-live
inventory without keyboard input. The private logs remain on the installer
USB; no capture files or device serials are committed. The live clock reset
to July 27, so the log timestamps do not identify the physical test date.

All seven markers are present: `EARLY`, `PORTS`, `GRAPHICAL_START`,
`LATE_CORE`, `LATE`, `WIFI`, and `COMPLETE`. The owner confirmed that the text
progress screen appeared and `noprompt` allowed automatic poweroff.

## Observations

| Area | Evidence | Interpretation |
|---|---|---|
| Graphics | GNOME reached Wayland, but only `simpledrm` on `simple-framebuffer.0` registered. There was no `/dev/dri/renderD*`; ACPI `QCOM0FF5` had no driver or platform device. GNOME reported no hardware acceleration, and Xwayland fell back to software. | The visible desktop did not use the native Adreno GPU. The loaded `msm` module did not bind to this ACPI-described GPU. `eglinfo`, `glxinfo`, and `vulkaninfo` were absent, so no standalone Mesa renderer report was captured. |
| USB-C | The owner connected USB-C storage to each left port during its 30-second window. The udev monitor recorded no events; early and both port-window kernel logs were identical. USB topology did not change. `/sys/class/typec` and `/sys/class/usb_role` were empty. ACPI `USBC000` reported status 0. | Neither storage connection visibly enumerated in this boot. The data do not isolate connector, power delivery, USB routing, or ACPI binding as the cause. |
| Wi-Fi | The first probe could not load `ath12k/QCC2072/hw1.0/amss.bin`. The bounded retry with SHA-256-verified upstream firmware reached QCC2072 chip ID `0x21`, family `0x4`, then failed the `board-2.bin` lookup for PCI `17cb:1112`, HP subsystem `103c:8ef3`, QMI chip 33, board 255. Only loopback remained. | The upstream firmware image can start this radio in RAM; the tested board database has no usable HP match. The bind command's exit status 0 does not indicate working Wi-Fi. |
| Input, audio, and power | Only the lid switch appeared under Linux input. No I²C adapters, ALSA soundcards, or Linux power-supply devices appeared. `QCOM0F10` controllers remained unbound. | Keyboard, touchpad, audio, and battery reporting remain unavailable in this boot. The charger was not functionally tested by this capture. |
| Bluetooth and services | No Bluetooth class device appeared. `pd-mapper.service` failed with `no pd maps available`. | Bluetooth and DSP service paths need separate driver and firmware-state investigation. This service failure alone does not explain every missing subsystem. |

The right USB-A installer, internal camera, PCI Wi-Fi endpoint, and internal
NVMe still enumerated. The internal NVMe partitions were listed but not
mounted by the collector. Kernel arguments included `clk_ignore_unused` and
`pd_ignore_unused`, so this run does not validate normal power gating.
*(Correction 2026-09-26: no Linux clock, RPMh, or power-domain provider binds
in this ACPI boot, so those arguments were no-ops and firmware clock state
persists regardless. See `docs/repository-audit-2026-09-26.md`.)*

## Next work

1. Trace the HP `QCOM0FF5` ACPI GPU device against the kernel's Adreno binding
   path. The live image contains Glymur GMU firmware, but the GPU never bound.
2. Examine the HP/QCC2072 board-data source and exact board selection without
   treating Windows firmware files as interchangeable with Linux `board-2.bin`.
3. Trace the ACPI UCSI/Type-C and USB controller dependencies before another
   USB-C boot attempt. The timed hotplug result is reproducible; repeating the
   same inventory is unlikely to narrow the cause.
