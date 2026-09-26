# Ubuntu ACPI Live Capture: 2026-09-25

The second controlled boot used the right USB-A port and the Ubuntu 26.04.1
ARM64 installer. Collector version 2 completed and powered the system off.
The private, hash-verified copy is under
`.work/ubuntu-live-boot-20260925/20260727T204532Z.t0ZwPZ/` (34 files including
`COMPLETE`). The laptop clock again reported July 27; that is not the collection
date. The original installer GRUB configuration was restored afterward and
hash-verified.

## What the new evidence establishes

- The running kernel has `CONFIG_ACPI=y`, `CONFIG_I2C=y`,
  `CONFIG_I2C_QCOM_GENI=m`, and `CONFIG_QCOM_GENI_SE=y`. `i2c_qcom_geni` and
  `i2c_hid_acpi` were loaded, but no I²C adapter or keyboard/touchpad input
  appeared.
- ACPI enumerated five `QCOM0F10` controller devices, including `I2C5` and
  `I2C9`. Their platform-device `uevent` records contain no `DRIVER` field;
  they were not bound to the GENI I²C driver. The absence of the ACPI ID in the
  reviewed mainline and Qualcomm `qcom-next` driver is a concrete gap, but an
  ID-only patch is not yet established as safe or sufficient.
- The ACPI `USBC000` device reported `status=0`; no Type-C class devices were
  recorded. `QCOM0F9D:00` was present without a driver in its platform-device
  `uevent`. The right USB-A installer again enumerated at 5 Gbit/s on bus 3;
  this boot did not test a device on the left USB-C ports.

The collector's old `readlink -f` output can print a path even when the final
`driver` link is absent. Use the `uevent` `DRIVER` field, not those printed
paths, to assess binding in this capture. The repository collector has been
corrected for future runs. `efibootmgr` was unavailable and the Secure Boot
query returned nonzero; neither affected collection.
