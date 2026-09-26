# Ubuntu Live Boot Results — 2026-09-15

## Capture

The Ubuntu 26.04.1 ARM64 live environment booted through UEFI/ACPI on the
target without a supplied DTB. The automated collector completed and wrote 29
files, including `COMPLETE`, to the FAT32 boot partition under
`glymur-logs/20260727T204533Z/`. The collector's reported system clock was
2026-07-27T20:45:33Z, which differs from the capture date and should not be
used as the evidence date.

The USB persistence partition (`/dev/sda2`, `casper-rw`) reported ext3 I/O and
journal errors during shutdown. The collector output is on `/dev/sda1` and is
complete; the persistence partition should not be trusted for future evidence
until checked separately.

## Confirmed Linux Results

- Kernel: Ubuntu `7.0.0-30-generic`, `aarch64`; ACPI/PSCI initialization completed.
- PCI domain 4 exposed Qualcomm WLAN endpoint `0004:01:00.0` (`17cb:1112`).
- PCI domain 5 exposed Samsung NVMe endpoint `0005:01:00.0` (`144d:a80f`); the
  internal NVMe namespace and partitions were enumerated.
- Two Qualcomm xHCI controllers registered. Linux detected the internal HP
  camera and the SanDisk installer as USB devices. The installer was on
  `QCOM0F9A:00` bus 3 at 5 Gbit/s through the right USB-A port; this does not
  establish USB 2.0 HID or left USB-C operation.
- The `ath12k_wifi7_pci` driver reached the WLAN device, but Ubuntu media did
  not contain `ath12k/QCC2072/hw1.0/amss.bin`; Wi-Fi initialization failed for
  missing firmware, not for PCI enumeration.
- No I²C adapters registered. The only Linux input device was the ACPI lid
  switch; no keyboard, touchpad, or USB HID input device was enumerated. The
  collector did not record ACPI device enumeration or the running kernel's
  I²C driver configuration, so it cannot prove which prerequisite failed first.

## Interpretation

The ACPI path is viable for continued diagnosis. The input failure is now
narrowed to Linux platform/I²C controller registration, ACPI resource handling,
or the corresponding HID child paths. USB is not globally absent: xHCI,
camera, and mass storage work, while physical-port mapping and USB HID remain
unresolved. Do not create or boot a guessed DTB from this result; use the
captured Linux/ACPI evidence to identify the missing controller resources first.
