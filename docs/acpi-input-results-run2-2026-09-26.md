# ACPI Input Test, Second Run: September 26, 2026

This run used collector v2 with the FIFO-depth fix in `glymur_geni_i2c.ko`
(SHA-256 `1332d75c...`) and the unchanged `glymur_acpi_gpio.ko`
(`9ac2fbd8...`) on the stock Ubuntu `7.0.0-30-generic` live kernel, with no
DTB. Every stage checkpoint and `COMPLETE` were saved, and there was no oops.
The private logs are in `.work/acpi-input-run2/`.

**Result: the internal keyboard, touchpad, and touchscreen work under Linux.**
Wi-Fi scanning works again.

| Stage | Result |
|---|---|
| 0: Wi-Fi | `wlo1` came up with the private HP `board-2.bin` and a scan succeeded (reproduced from run 1) |
| 1: GPIO module | Bound `QCOM0F0C:00`. Summary IRQ is GSI 240. |
| 2: I²C1 + I²C5 | Both adapters registered with ACPI `CLKD` 400 kHz timing `(div 2, high 5, low 12, cycle 24)`, the same values firmware set. `i2c_hid_acpi` bound `QTEC0001:00` (keyboard, HID `0416:C300`) and `ELAN0189:00` (touchpad, HID `04F3:32EF`, `hid-multitouch`). |
| 2b: input window (45 s) | Keyboard: `EV_KEY=162`, plus LED events. Touchpad: `EV_ABS=2232`, `EV_KEY=128`. |
| 3: I²C9 | Bound from sysfs with the same timing. `ELAN2513:00` (touchscreen, HID `04F3:44BF`, `hid-multitouch`) produced `EV_ABS=7740` in 30 s. |
| 4: IC10 (EC) | **Refused by the probe gate:** `proto=3 clk=0x21` but FIFO disabled, meaning the engine is in GPI DMA mode. No transfer was attempted. |

Only event counts were recorded; key codes and coordinates were not.

Interrupt counts at the end of the run:

| Interrupt | Count |
|---|---|
| TLMM summary, GSI 240 | 5244 |
| Keyboard, ACPI pin 704 (GPIO 67) | 350 |
| Touchpad, pin 896 (GPIO 3) | 2168 |
| Touchscreen, pin 51 (direct) | 2726 |
| Engine GSI 4188 (I2C1) | 376 |
| Engine GSI 4192 (I2C5) | 2210 |
| Engine GSI 385 (I2C9) | 2726 |

- No "nobody cared", I²C timeout, NACK, or i2c-hid error appeared. The only
  message was one `IRQ triggered but there's no data` at touchscreen init,
  which is normal for the post-reset interrupt.
- `set_type` programmed all three pins level-low with target KPSS
  (`intr_cfg 0x70`). The TLMM summary route used by OpenBSD therefore works
  on this HP; the PDC route is not needed for runtime interrupts.

## What this establishes

1. The HP ACPI description is sufficient for input, together with the
   two pieces of logic the modules add: `CLKD` timing and PDC pin
   translation.
2. In ACPI mode, firmware leaves I2C1, I2C5, and I2C9 clocked and
   configured, and Linux can use them without any clock, interconnect, or
   power-domain driver.
3. The device facts are confirmed on hardware. They are the evidence needed
   for the corresponding DT nodes:

   | Device | Bus / address | HID ID | Interrupt |
   |---|---|---|---|
   | Keyboard | I2C1 / 0x3A | `0416:C300` | GPIO 67 |
   | Touchpad | I2C5 / 0x15 | `04F3:32EF` | GPIO 3 |
   | Touchscreen | I2C9 / 0x10 | `04F3:44BF` | GPIO 51 |

   All use level-low interrupts.

## Open items

- **EC (IC10):** it needs GPI DMA. `_DEP` names `QGP1` (`QCOM0F88`), the
  GPI DMA engine. `i2c_acpi_find_bus_speed()` found no child device for it,
  because the EC is reached only through the `ICCR` OpRegion, so the driver
  fell back to the 100 kHz `CLKD` row. The `ECIC` connection in SSDT `8F47`
  declares 400 kHz. Lid, HP WMI, and keyboard-backlight AML depend on this
  bus.
- **Battery and AC:** `_PSR` still fails with `No handler for Region [ROP1]
  [GenericSerialBus]` (the ABD/PMIC-GLink path). The thermal zones read
  `-200`.
- **Suspend/resume, wake from keyboard or touchpad, and runtime PM** of the
  I²C engines are untested.
- **Upstreaming.** The equivalent qcom-next changes are:
  - `CLKD` timing;
  - `i2c_acpi_find_bus_speed()`;
  - FIFO-only operation without a wrapper, including the FIFO-depth fix;
  - the `QCOM0F10` ID;
  - ACPI support in `pinctrl-glymur` with PDC translation (RFC 0002/0003,
    or an OpenBSD-style standalone driver).
