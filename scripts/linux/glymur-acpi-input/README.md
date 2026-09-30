# ACPI input kit (stock Ubuntu live kernel)

Out-of-tree modules and scripts that brought up the keyboard, touchpad,
touchscreen and EC bus on the stock Ubuntu `7.0.0-30-generic` live kernel.
The SSD install now uses in-kernel drivers instead (`patches/kernel/`). See
`docs/acpi-input-test-2026-09-26.md` and
`docs/acpi-input-results-run2-2026-09-26.md`.

## `glymur-acpi-input-test.sh`

The default-off live test: it loads the hash-pinned ACPI TLMM GPIO and ACPI
GENI I²C modules in stages. Before each riskier step, it saves a checkpoint
to the serial-verified installer FAT volume. It never writes internal
storage.

Stages:
- **0, Wi-Fi.** HP board data in RAM. The private `board-2.bin` adds
  `bdwlan_qcc2072_1p0_ncm820A.elf`, which Windows binds to `SUBSYS_8EF3103C`.
  Only network counts and channels are recorded.
- **1, GPIO.** Only allow-listed pins are touched.
- **2, keyboard and touchpad buses.** I2C1 and I2C5.
- **3, touchscreen bus.** I2C9.
- **4, EC bus (IC10).** The HP EC is at 0x76 (SSDT `8F47`): lid, HP WMI and
  keyboard backlight. Battery and AC go through `\_SB.ABD` (PMIC GLink)
  instead. Ubuntu's 7.0 arm64 kernel has no `hp_wmi`, so only
  firmware-initiated AML uses the EC.

After a kernel oops, a normal poweroff blocks on the crashed probe's device
lock, so the test forces an immediate restart instead.

## `glymur-live-desktop-setup.sh`

The interactive live desktop, and the "Glymur workstation" boot:
- It loads the same modules for the keyboard (I2C1), touchpad (I2C5) and
  touchscreen (I2C9).
- It gives ath12k its firmware plus the private HP board data, in RAM.
- It blocks suspend and hibernate, which are untested.
- If the kit has them, it binds the EC bus: QGP1, the GPI DMA engine,
  first, then IC10 in GSI mode. It then loads `glymur_acpi_ged.ko`, `evged.c`
  with `GpioInt` support, because ECGE's `_EVT` reads the EC:
    - GPIO 66 is the EC event (ECGE);
    - GPIO 92 is the lid (LIGE).
- In workstation mode (`glymur.workstation=1`, persistent boot only), the
  first boot unpacks the staged repository bundle (with `.work`) into the
  persistent home.

## `glymur-ec-gsi-live-test.sh`

    sudo glymur-ec-gsi-live-test.sh <module-dir> <log-root> [--transfer]

The live EC bus test, run once per boot before anything else touches QGP1.
- It binds QGP1 (`glymur_gpi_dma.ko`), then IC10 (`glymur_geni_i2c_gsi.ko`).
  The ACPI I²C OpRegion handler then runs `IC10._REG`, which only sets
  `AVBL`.
- `--transfer` also reads EC register 0xB2 at 0x76, the access the lid
  `_EVT` handlers make.
- The modules can't be unloaded, so a wedged bus needs a reboot.
