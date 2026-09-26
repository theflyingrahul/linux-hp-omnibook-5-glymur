# ACPI Input Test, First Run: September 26, 2026

The first run of the "Glymur ACPI keyboard/touchpad test (RAM live)" entry
(collector version 1) booted Ubuntu `7.0.0-30-generic` from the right USB-A
port. The collector reached `COMPLETE`, but the machine did not power off and
the progress screen stopped updating after `BEFORE_I2C`. The private logs are
in `.work/acpi-input-run1/`.

## Results

| Stage | Result |
|---|---|
| 0: Wi-Fi | **Working.** See below. |
| 1: GPIO module | **Loaded.** See below. |
| 2: I²C module | **Kernel oops** in probe; `insmod` exited with 139. No I²C adapter, so no HID devices and zero input events. |
| 3: Touchscreen and 4: EC | Not tested. Binding returned "Permission denied" because the crashed probe still held the driver and device state. |
| Lid | `/proc/acpi/button/lid/*/state` reported `open` before and after. |
| WMI | Ubuntu's arm64 kernel does not ship `hp_wmi`. |

### Wi-Fi

The upstream `firmware-2.bin` plus the private `board-2.bin` containing the
HP entry (`bdwlan_qcc2072_1p0_ncm820A.elf`) brought the chip up:

- QCC2072 chip id `0x21`; firmware `WLAN.COL.1.0.c2-00277`.
- Interface `wlo1` appeared and came up.
- One scan found 13 BSSs on 2.4 GHz, 5 GHz, and 6 GHz channels.
- The PHY is self-managed with world regulatory domain `00`.
- No ath12k errors occurred after the interface registered. The only failure
  in the log is the expected first attempt without firmware.

No association was attempted.

### GPIO module

`glymur_acpi_gpio` bound `QCOM0F0C:00`. It registered summary IRQ 164 (GSI
240) and all 16 PDC slots. The mapping matches the offline analyzer,
including 704 → IRQ 751 → GPIO 67 and 896 → IRQ 658 → GPIO 3. It adds one
slot the analyzer did not print: 960 → IRQ 4147 → GPIO 92.

Firmware state of the allowed pins:

| GPIO | ctl | io | intr_cfg | Reading |
|---:|---|---|---|---|
| 3 (touchpad) | `0x0` | `0x0` | `0xe2` | GPIO function, no pull; line **low** |
| 51 (touchscreen) | `0x1` | `0x1` | `0xe2` | pull-down; line high |
| 67 (keyboard) | `0x1` | `0x1` | `0xe2` | pull-down; line high |
| 92 (lid) | `0x0` | `0x1` | `0xe2` | line high |

`intr_cfg 0xe2` means interrupt disabled, target field 7 (not KPSS), and the
polarity bit set. No pin was already routed to the application processor, so
the driver masked nothing.

The touchpad's active-low interrupt line reads low. That fits either an
unpowered touchpad or one that has asserted its post-reset interrupt;
i2c-hid will show which.

## Cause of the oops

```text
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008
pc : geni_se_get_qup_hw_version+0xc/0x28
lr : geni_i2c_probe+0x57c/0xdb8 [glymur_geni_i2c]
```

`geni_se_get_tx_fifo_depth()` is an inline helper in `geni-se.h`. It reads
`QUPV3_HW_VER_REG` from `se->wrapper->base` to choose the `SE_HW_PARAM_0`
depth mask. The test driver deliberately sets a NULL wrapper on ACPI.
`docs/repository-audit-2026-09-26.md` point 4 missed this use.

Upstream v7.0's own ACPI IDs are likely exposed to the same fault. The
GENI wrapper driver has no ACPI match, so an ACPI I²C device's parent
should not carry wrapper drvdata. This was not verified on those machines. This oops happened before any
register write or I²C transfer.

**Fix** (in `derive-geni-i2c.py`): without a wrapper, read `SE_HW_PARAM_0`
directly and accept the depth only if the 6-bit and 8-bit masks agree. The
September 25 snapshots (`0x202029e8`, `0x20202868`) give 32 under both
masks.

After the fix, the remaining imported wrapper users are unreachable for this
device:

- DMA prep/unprep, because the driver runs FIFO-only.
- SE firmware loading, because probe requires protocol I²C.
- Clock on/off, which returns early for ACPI.

## Why the laptop froze

After the oops, the probing task died with the driver-core device lock
still held. The collector kept running and saved every checkpoint, but the
final `poweroff` blocked in `device_shutdown()` on that lock. The VT stopped
redrawing after the oops, so the screen looked frozen from `BEFORE_I2C`
onward.

Collector version 2 changes:

- After a failed I²C load it skips the dependent stages.
- If `dmesg` shows an oops, it forces a `sysrq-b` restart, which runs no
  device shutdown callbacks, instead of a hanging poweroff. The installer is
  already unmounted at that point.

## Restaged kit

| File | SHA-256 |
|---|---|
| `glymur_geni_i2c.ko` (FIFO-depth fix) | `1332d75cc9d06edeb75a0c1a821e80bb2b58252abf03c600db03a5f530f30db6` |
| `glymur-acpi-input-test.sh` (v2) | `c315e505551b747eaf325148913655b0d4c5917f25bb7016ee302f2696f825a9` |
| `glymur_acpi_gpio.ko` (unchanged) | `9ac2fbd814f0f73531ce9c6ce5a1d54d1604ed63a24bdea1e0b0555f33dd9b24` |

The GRUB file is unchanged from the first staging. `chkdsk` is clean.
