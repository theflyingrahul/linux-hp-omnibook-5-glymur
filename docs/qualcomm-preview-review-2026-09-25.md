# Snapdragon X2 Preview: HP OmniBook 5 Review

Reviewed 2026-09-25. This note separates Qualcomm's public reference-platform
results from observations on the HP OmniBook 5 16-bf1xxx (board 8F47).

## What Qualcomm has published

Qualcomm's [September 23 early developer preview](https://www.qualcomm.com/developer/blog/2026/09/announcing-linux-on-snapdragon-x2-series-early-developer-preview)
describes staged X2 laptop enablement. Its validated environment is Debian 13
(Trixie) with a custom kernel; it explicitly says readiness varies by OEM and
processor variant. The linked [X2 build overview](https://docs.qualcomm.com/doc/SP80-A0399-4/topic/snapdragon-x2-linux-software-overview.html?Content+for=Linux&facet=Build&product=63746125550838921)
names an SC8480XP reference platform and prebuilt/full-firmware build paths.
Neither source names this HP board or promises a ready Fedora image.

The linked [Debian image recipes](https://github.com/qualcomm-linux/qcom-deb-images)
recommend Qualcomm's `qcom-next` integration kernel for their CI images; a
plain Debian kernel is the default for local recipes. Those recipes and their
flashing examples are not instructions to write this laptop's internal disk or
firmware. Qualcomm's [compute-device discussion](https://github.com/qualcomm-linux/qcom-deb-images/issues/227)
describes Windows-on-Arm firmware with no usable DT and loading a selected DT
through GRUB or Stubble. Their [Glymur CI discussion](https://github.com/qualcomm-linux/qcom-deb-images/issues/394)
distinguishes that case from reference-board firmware that supplies a DT.

On September 25, we fetched `qcom-next` at
`a47c4c5aa34b866136077d023d7c9e78d5a2225b` and the image recipes at
`e2150b21fa303d5571d2fdb2a978ba5de7eb275b` into ignored WSL work
directories. The kernel is 7.3.0-rc2 and includes Glymur CRD DT files but no
HP OmniBook 5 DT. The image recipe's Glymur target is explicitly
`glymur-crd` with its CRD DTB and CDT. The unmodified Qualcomm kernel and CRD
DTB compiled successfully in WSL on September 25; see
`qualcomm-acpi-gap-2026-09-25.md`. Neither was booted on this HP machine.

## What this HP machine establishes

The private `.work/ubuntu-live-boot-20260915/20260727T204533Z/` capture is a
successful Ubuntu 26.04.1 UEFI/ACPI boot on the HP board, with no supplied
DTB. The kernel log shows 12 CPUs, the architected timer, PCI domains 4 and 5,
NVMe, two xHCI controllers, a USB camera, and installer storage. It shows no
I²C adapter; Linux input contains only the lid switch. The capture has 29
files **including** `COMPLETE`. Its July 27 clock reading is inconsistent with
the September 15 collection date. `COMPLETE` means the collector finished,
not that every subsystem worked.

The successful installer used the right USB-A port. The owner reports that
booting the same media through either left USB-C port, especially through a
hub, loses the installer disk mid-boot. That is a separate, uncaptured boot
failure: the post-boot collector cannot run after the live medium disappears.
The working capture shows the installer at 5 Gbit/s on `QCOM0F9A:00` bus 3;
it does not establish USB-C routing or USB 2.0 HID functionality.

The captured ACPI resources describe `QCOM0F10` I²C controllers and HID
clients `TCPD` on `I2C5` (7-bit address `0x15`) and `TSC1` on `I2C9` (address
`0x10`). These address fields follow the [ACPI I²C resource layout](https://uefi.org/htmlspecs/ACPI_Spec_6_4_html/06_Device_Configuration/Device_Configuration.html).
They do not establish that the clients are powered or usable in Linux.

## Driver gap and uncertainty

The pinned mainline `i2c-qcom-geni.c` and the reviewed
[`qcom-next` driver at reviewed commit](https://github.com/qualcomm-linux/kernel/blob/a47c4c5aa34b866136077d023d7c9e78d5a2225b/drivers/i2c/busses/i2c-qcom-geni.c)
list ACPI IDs `QCOM0220` and `QCOM0411`, but not `QCOM0F10`. Their probe reads
wrapper data from the parent device. The shared GENI resource code permits an
ACPI device to lack a named `se` clock, while the I²C code later queries that
clock. These paths need review before any experimental ID addition. The Ubuntu
collector did not record kernel configuration, ACPI device enumeration, or
platform-device driver links, so the missing ID alone does not fully explain
the observed failure. Reference DT support for a QUP controller does not prove
that its ACPI representation is supported.

## Next validation

1. The September 25 ACPI capture confirms `CONFIG_I2C_QCOM_GENI=m` and that
   the module loaded without binding the five `QCOM0F10` controllers; see
   `ubuntu-live-boot-results-2026-09-25.md`.
2. Trace any `QCOM0F10` probe path through parent, clock, power, IRQ, and HID
   child enumeration before attempting an ACPI driver patch. Compile first;
   test on removable media only after reviewing the resulting boot path.
3. Evaluate a board-specific DT route only with HP-specific resources and a
   known boot-loader selection method. Use Qualcomm's Debian build as a
   comparison baseline; keep Fedora ARM64 as the intended installed OS.

## Repository audit scope

This review checked the announcement and linked primary sources, the captured
Linux results, ACPI I²C resources, and the GENI probe/resource source. All
repository Bash files now parse under WSL after LF conversion; Python files
compile; the Windows PowerShell static tests and an isolated additive-merge
test pass. The Windows Day-0 SHA-256 manifest revalidated. The revised
collector subsequently completed a second target boot. Qualcomm's unmodified
kernel and CRD DTB compiled in WSL, but the Debian image has not been built
and neither Qualcomm artifact has been booted on this HP laptop. No claim of
full hardware readiness follows from these checks.
