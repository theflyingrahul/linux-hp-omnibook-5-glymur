# EC Bus (IC10) GPI DMA Live Test: September 26, 2026

This first live-workstation experiment ran on the Glymur workstation boot
(stock Ubuntu `7.0.0-30-generic`, no DTB, input modules loaded) without a
reboot. Private logs are in `.work/ec-gsi-live-20260926T202437Z/`.

**Result: the GPI engine bound and its command path works. IC10 did not
bind, because a generic DMA client took the channels first.** The run had
no oops, and keyboard, touchpad and Wi-Fi kept working. A clean retry needs
a reboot.

## Why the EC needs GPI DMA

The run-2 input test found IC10 (`QUP_1_SE_1`, `0xA84000`) in GSI mode:
FIFO is disabled, so every transfer must go through the QUP1 GPI DMA engine
`\_SB.QGP1` (`QCOM0F88`), which is listed in IC10's `_DEP`.

## Evidence gathered on the live system

| Fact | Value |
|---|---|
| Exception level | All CPUs started at EL2; Linux owns the SMMUs through IORT |
| SMMU unmatched streams | Bypass (`arm_smmu.disable_bypass=N`; `CONFIG_ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT` unset) |
| `QGP1` IORT mapping | None. Named components cover GPU, ADSP, USB and others, not QGP0/1/2. |
| `QGP1._CCA` | 0 (non-coherent) |
| `QGP1` MMIO | `0xA04000`, length `0x58000`: 0x4000 into DT `gpi_dma1` (`0xA00000`, length `0x60000`) |
| `QGP1` interrupts | GIC SPI 279, 280, 281: DT `gpi_dma1` GPII 0-2 |
| IC10 | QUP1 SE1, GIC SPI 354; DT `i2c9` uses `dmas = <&gpi_dma1 {0,1} 1 QCOM_GPI_I2C>` |
| EC connection | `I2cSerialBusV2` 0x76 at 400 kHz, reached only through the `ICCR` GenericSerialBus OpRegion |
| `IC10._REG` | Only sets `AVBL`; it makes no EC access |
| Consumers of `AVBL` | Lid `_EVT` handlers (read `CMB2`, register `0xB2`), `_PS0`/`_PS3` methods, HP WMI (`WMID`) helpers |
| HP WMI device | `PNP0C14:02` is a child of IC10. The stock Ubuntu arm64 kernel has no `CONFIG_ACPI_WMI`. |

With bypass and no IORT entry, an ACPI-bound GPI device performs DMA with
physical addresses and non-coherent cache maintenance, which the DMA API
handles.

## Test modules

Both are derived from Linux v7.0 by hash-checked scripts in
`scripts/linux/glymur-acpi-input/`:

- `derive-gpi-dma.py` produces `glymur_gpi_dma.ko` from `drivers/dma/qcom/gpi.c`.
  - It binds `QCOM0F88` at an allowlisted base (default `0xa04000` only).
  - The GPII count comes from the ACPI interrupt count (3, mask `0x7`).
  - The EE offset is the sm6350-style `0x10000` plus the 0x4000 ACPI window
    skip. All touched registers (block offsets `0x20000`-`0x23404` plus
    `0x4000` per GPII) stay inside the ACPI window.
  - It exports `glymur_gpi_dma_request(chid, seid, protocol)` in place of
    the DT `dmas` xlate.
- `derive-geni-i2c.py --gsi` produces `glymur_geni_i2c_gsi.ko`.
  - It binds only engines with FIFO disabled (default `0xa84000`, seid 1).
  - It requests its channels from `glymur_gpi_dma`.
  - Timing still comes from `CLKD`.
  - The default FIFO output of the script is byte-identical to before.

## What happened

1. `glymur_gpi_dma.ko` bound `QCOM0F88:01` with 3 GPIIs.
2. At registration, `async_tx` claimed all three GPIIs. The live image had
   autoloaded `raid456`, which pulls in `async_tx`, and upstream `gpi.c` does
   not set `DMA_PRIVATE`. Each GPII was started with seid 0 and protocol 0:
   - `EV ALLOCATE` and both `CH ALLOCATE` commands completed through the
     GPII interrupt, so register access, command submission and interrupt
     delivery all work.
   - `CH START` timed out. The likely cause is that seid 0 is SE0 (I2C9,
     the touchscreen), which is in FIFO mode and never completes a GSI
     handshake.
   - The cleanup `DE ALLOC` commands also timed out.
3. The GSI I²C probe found no free GPII and failed with `-EBUSY`.
4. After unloading the idle `raid456`/`async_tx` stack (there were no md
   arrays), a sysfs rebind failed with `protocol did not match 3 != 0`. The
   failed initialization left stale channel state in the driver, and the
   module cannot be unloaded.
5. In the upstream error path, the GPII event rings stay allocated in
   hardware after their memory is freed. The GPIIs are idle, but no more
   commands were sent to this engine during this boot.

## Fix and next step

- The derived GPI driver now sets `DMA_PRIVATE`, so only
  `glymur_gpi_dma_request()` can claim channels.
- `glymur-ec-gsi-live-test.sh` now stops if any QGP1 channel is in use
  before IC10 requests one.
- Next boot: before anything else touches QGP1, run:

      sudo scripts/linux/glymur-acpi-input/glymur-ec-gsi-live-test.sh \
          "$PWD/.work/native-build-gsi-v2" "$PWD/.work" --transfer

Open questions:

- Does `CH START` complete for seid 1 with protocol I²C?
- Does one EC read (`0xB2` at `0x76`) succeed?
- Lid events also need `_AEI` handling (`acpi_gpiochip_request_interrupts`)
  in `glymur_acpi_gpio.ko`, which it does not do yet.
