# ACPI Keyboard/Touchpad Test Kit: September 26, 2026

Goal: get the internal keyboard and touchpad working in the stock Ubuntu
26.04 ARM64 live kernel (`7.0.0-30-generic`) without replacing that kernel
or booting a DTB. The same boot also:

- retries Wi-Fi with the HP board data;
- probes the touchscreen bus;
- probes the embedded-controller bus.

One reboot therefore answers five questions.

The kit is **staged but not yet run on hardware**.

## Why two out-of-tree modules

Input needs two things, and the stock kernel has neither for this HP:

1. **An I²C adapter for the ACPI `QCOM0F10` controllers.**
   - The in-tree `i2c-qcom-geni` matches only `QCOM0220` and `QCOM0411`.
   - In v7.0 it would also pass an error-pointer clock to `clk_get_rate()`
     (see `docs/repository-audit-2026-09-26.md`).
2. **A GPIO interrupt provider for ACPI `GIO0` (`QCOM0F0C`) that understands
   PDC-encoded pins.**
   - The keyboard uses ACPI pin 704 (GPIO 67) and the touchpad uses pin 896
     (GPIO 3).
   - `CONFIG_PINCTRL_MSM=y` is built into the Ubuntu kernel and has no ACPI
     match.
   - The PDC translation in RFC 0003 changes built-in gpiolib code.

   Neither can be tested by loading a module, so the kit ships a small
   standalone driver instead.

Everything else is Ubuntu's own code:

- `i2c_hid_acpi` matches the `PNP0C50` compatible ID of `ECKB` (`QTEC0001`,
  0x3A on I2C1), `TCPD` (`ELAN0189`, 0x15 on I2C5), and `TSC1` (`ELAN2513`,
  0x10 on I2C9).
- `hid-multitouch` handles the touchpad and touchscreen.

All three devices declare 400 kHz I²C and level-low, pull-up `GpioInt`s.

## Module 1: `glymur_acpi_gpio.ko`

Source: `scripts/linux/glymur-acpi-input/glymur_acpi_gpio.c`. It is a new
driver modelled on OpenBSD `qcgpio.c`, using the register layout from
`pinctrl-glymur.c`.

Design and safety choices:

- **Default-off.** It binds only with `enable=1` and only to
  `QCOM0F0C` at MMIO `0x0F100000`.
- **Checks firmware before binding.** It requires the GPIO-count `_DSM` to
  report 250. The PDC map is built from the `GIO0._CRS` ExtendedIRQ order and
  the CIPR package that the PDC `_DSM` returns; a malformed or ambiguous table
  aborts probe.
- **Allow-list.** Only the pins in the `pins=` list (default `3,51,67,92`)
  are valid. PDC offsets are valid only at exact multiples of 64 that map to
  an allowed pin. gpiolib therefore never reads or writes any other TLMM
  pin, which avoids secure or reserved pins.
- **Read-only pins.**
  - There is no output, mux, pull, or drive support.
  - `direction_input` succeeds only for a pin that firmware already set as
    a GPIO-function input.
  - Pin 92 is only read, for the `GIO0.LIDR` lid OpRegion.
- **Interrupt routing.**
  - Interrupts use the TLMM summary IRQ, the first `GIO0` interrupt
    (GSI 240).
  - `intr_cfg` is set to target KPSS (3) with raw status, the requested
    level or edge sense, and status cleared.
  - The summary handler returns `IRQ_NONE` if no owned pin fired, so a
    firmware-enabled foreign pin cannot storm the CPU undetected.
- **No `_AEI` events.** `GIO0._AEI` (pin 126, a GPU notification) is not
  requested.
- **Firmware state is logged.** Probe logs the ctl/io/intr state of every
  allow-listed pin. It masks only a pin that firmware already routed to the
  application processor.

## Module 2: `glymur_geni_i2c.ko`

This module is derived from Linux v7.0 `drivers/i2c/busses/i2c-qcom-geni.c`
by `derive-geni-i2c.py`. That script checks the source's SHA-256 against the
v7.0 file, which matches Ubuntu's. The full delta, about 120 changed lines, is
in `glymur_geni_i2c-vs-v7.0.diff`.

| Change | Reason |
|---|---|
| Matches only `QCOM0F10`; renamed `glymur_acpi_geni_i2c`; no OF table | Stock module keeps every other device |
| `allow=` MMIO-base allow-list (default I2C1 `0xb80000`, I2C5 `0xb90000`), checked before any MMIO | Only these two engines were read-tested |
| Absent ACPI `se` clock → `NULL` | Avoids the v7.0 `clk_get_rate(ERR_PTR)` fault |
| Bus speed from `i2c_acpi_find_bus_speed()` if no `clock-frequency` | Children declare 400 kHz; the v7.0 default would silently use 100 kHz |
| Timing from the controller's `CLKD` row for that speed | Writes the same `CLK_CFG=0x21`, `SCL=0x00503018` firmware set |
| No wrapper on ACPI → FIFO only | SE DMA needs the DT wrapper device |
| Probe refuses unless protocol = I²C, serial clock enabled, FIFO enabled | Never loads SE firmware or touches an unconfigured engine |

The rest of the v7.0 driver is unchanged, including its IRQ-driven transfer,
timeout, and abort handling. The engine interrupt is a direct GIC SPI from
`_CRS` and does not depend on the GPIO module.

## Collector stages

Boot entry: **"Glymur ACPI keyboard/touchpad test (RAM live)"**. It adds
`toram nopersistent noprompt`, is optional, and is not the default. The
collector is `glymur-acpi-input-test.sh`. It saves a checkpoint to the
installer before every riskier step, so a hang still leaves everything up
to that point.

| Stage | Action | Checkpoints |
|---|---|---|
| Preconditions | RAM boot, kernel `7.0.0-30-generic`, installer UUID and serial, pinned SHA-256 of both modules and the counter | `EARLY` |
| 0 | Wi-Fi: RAM-only QCC2072 probe with upstream `firmware-2.bin` plus a private `board-2.bin` that adds the HP board entry; if a netdev appears, one scan recording only the network count and channels | `WIFI` |
| 1 | `insmod glymur_acpi_gpio.ko enable=1` | `BEFORE_GPIO`, `GPIO` |
| 2 | `insmod glymur_geni_i2c.ko allow=I2C1,I2C5`; `i2c_hid_acpi` and `hid_multitouch` load | `BEFORE_I2C`, `I2C` |
| 2b | **45 s: type and use the touchpad**; only per-device event-type counts are recorded | `INPUT` |
| 3 | Widen `allow`, bind I2C9 (touchscreen, never read before); **30 s: touch the screen** | `BEFORE_TOUCH`, `TOUCH` |
| 4 | Unload `hp_wmi`; widen `allow`, bind IC10 (EC bus); record lid state before and after | `BEFORE_EC`, `EC` |
| End | Kernel journal, then poweroff | `COMPLETE` |

IC10 is the HP embedded controller: I²C address 0x76, connection `ECIC` in
SSDT `HPQOEM 8F47`. Its `_REG` sets `IC10.AVBL`. The EC AML serves:

- lid state (`CMB2`, used by `LID0` and `GIO0._EVT`);
- the HP WMI device `WMID`;
- keyboard-backlight settings, some of which AML writes to EC storage.

For that last reason the collector unloads `hp_wmi` before the bind, so that
only firmware-initiated methods such as `_LID` use the EC during this test.
The probe refuses IC10 if firmware left it in GPI DMA mode (FIFO disabled).
IC10 depends on `QGP1`, so that outcome is possible.

**Battery and AC do not use IC10.** `CMBD._BST` and `CMPS._PSR` read
`\_SB.PMGK` fields that live in `\_SB.ABD.ROP1`. That is a GenericSerialBus
region of the Qualcomm ABD device (`QCOM1045`), which Windows serves through
PMIC GLink on the ADSP. `_BST` also returns a cached value while
`PMGK.LKUP` is zero, which is the same gate that hides `USBC000`. Battery,
AC, and USB-C therefore share one missing path: a running ADSP, GLink, and an
ABD OpRegion handler. That is the next subsystem to design; see "Next".

## Known risks

- An MMIO read of an unclocked engine can hang the SoC. I2C1 and I2C5 were
  read twice without issue; I2C9 and IC10 were not, which is why they run
  last and after checkpoints. A hang needs a forced power-off. The kit writes
  nothing to the NVMe, firmware, or BIOS settings.
- Keyboard and touchpad interrupts use the TLMM summary route that OpenBSD
  uses, not the PDC route Windows uses. Wake from suspend is out of scope.
- The i2c-hid probe performs the first real I²C transfer: the HID descriptor
  read. A failure is logged and does not retry indefinitely.

## Build and staging record

> The hashes below are from the first staging. The first run oopsed in the
> I²C module; the fixed and restaged hashes are in
> `docs/acpi-input-results-2026-09-26.md`.

```bash
# WSL, from ~/glymur-build
bash scripts/linux/glymur-acpi-input/build.sh .work/ubuntu-src/tree/linux-source-7.0.0 7.0.0-30-generic .work/glymur-acpi-input
bash scripts/linux/glymur-acpi-input/make-kit.sh .work/glymur-acpi-input <kit-dir>
```

Ubuntu source is `apt-get download linux-source-7.0.0` (7.0.0-31.31). Its
`i2c-qcom-geni.c` and `qcom-geni-se.c` are identical to v7.0; the headers are
`linux-headers-7.0.0-30-generic`. `checkpatch` found nothing in the GPIO
driver. Both modules report vermagic `7.0.0-30-generic SMP preempt
mod_unload modversions aarch64`, and the builds reproduced the same hashes.

| Kit file | SHA-256 |
|---|---|
| `glymur_acpi_gpio.ko` | `9ac2fbd814f0f73531ce9c6ce5a1d54d1604ed63a24bdea1e0b0555f33dd9b24` |
| `glymur_geni_i2c.ko` | `623cdd850c525e80cb4d2bfcfe76c95b0359890f3fb1dd0d1427fac58af4968c` |
| `glymur-input-counter.py` | `3c7221e9294af897286ccbcd5ce541ba4cfd293af5db7e294e5891899d58b83b` |
| `glymur-acpi-input-test.sh` (hashes pinned) | `ccc1750d3350038acf706a6e9ea91635191b74df9b109e9fd8ec1162f29aa495` |
| `wifi/board-2.bin` (private, not in Git) | `de345584ff4f59d44aeb399175005ad3dd1cb2d13476ffa158890d162871b747` |

Staged to `E:\glymur-tools\acpi-input\` on the SanDisk installer (FAT UUID
`07F8-1419`). Before staging:

- The previous `grub.cfg` was backed up to
  `.work/grub-before-acpi-input-20260926.cfg`. The edit only appended the new
  entry; the first 2,293 bytes are byte-identical.
- The September 26 inventory and USB hot-plug logs were copied to
  `.work/usb-logs-20260926/`.
- `chkdsk` reported no problems.

## Wi-Fi board data

The September 26 retry failed only at the board-data lookup:

```text
bus=pci,vendor=17cb,device=1112,subsystem-vendor=103c,subsystem-device=8ef3,qmi-chip-id=33,qmi-board-id=255
```

Upstream `ath12k/QCC2072/hw1.0/board-2.bin` (SHA-256 `6880d8e6...`) has
five names in four BOARD entries, none of them HP's. Each payload is an ELF
board-data file.

On this laptop, Windows binds `PCI\VEN_17CB&DEV_1112&SUBSYS_8EF3103C` through
`qcwlancol8480.inf` (installed as `oem121.inf`), section
`QcWlan_H_NCM820A.ndi`. That section's `BDFileName` is
`bdwlan_qcc2072_1p0_ncm820A.elf` (SHA-256 `960e9e93...`, 125,288 bytes).
Its ELF layout matches the upstream entries: ELF32, machine 40, one
`PT_LOAD` at `0x1000` of 123,600 bytes.

`scripts/linux/ath12k-board-add.py` appends that file under the HP name to a
copy of the upstream container, verifies a round trip, and writes the result
to `.work/wifi-board-20260926/board-2.bin` (SHA-256 `de345584...`). The file
contains Windows-derived data, so it stays private and must not be committed.

## Next

ACPI mode can reasonably provide input, Wi-Fi, NVMe, USB-A, and the lid.
GPU acceleration, audio, the ADSP-hosted PMIC GLink path (battery, AC,
USB-C/UCSI), and remoteprocs need drivers that Linux matches only through
DT: `msm`/Adreno, `q6v5_pas`, `pmic_glink`, LPASS, and the GCC/RPMh clocks.
The long-term route to a fully working Fedora install is therefore still an
evidence-built OmniBook 5 DTS.

The ACPI work supplies much of that evidence directly:

- I²C bus mapping and HID addresses (0x3A, 0x15, 0x10);
- interrupt GPIOs 67, 3, and 51;
- PCIe domains;
- the EC address;
- the Wi-Fi board data.

The results of this test decide how much of the input description can be
trusted in such a DTS.
