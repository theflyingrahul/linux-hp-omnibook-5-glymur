# Windows-Side Evidence for the Bring-Up Plan: September 27, 2026

This follows up `docs/qcom-next-first-boot-2026-09-27.md` and
`docs/hardware-bringup-plan-2026-09-27.md`, both written from the SSD install.
It uses the live Windows PnP tree on this laptop (read-only
`Get-PnpDevice`), the captured DSDT (private) and the qcom-next source at
`a47c4c5aa`. Three conclusions in those documents change.

## Correction: Wi-Fi does use the HP board data

The first-boot report concluded that ath12k runs on generic calibration,
because `/lib/firmware/ath12k/` has no `QCC2072/` directory and the chip
reports `board_id 0xff`. Neither fact means that:

- The SSD installer puts the upstream `firmware-2.bin` and the private HP
  `board-2.bin` in `/lib/firmware/updates/ath12k/QCC2072/hw1.0/`, which the
  firmware loader searches before `/lib/firmware/`.
- `board_id 0xff` is the chip's OTP board ID. It is part of the lookup key,
  not a fallback.
- The staged container has exactly this laptop's entry:
  `bus=pci,vendor=17cb,device=1112,subsystem-vendor=103c,subsystem-device=8ef3,qmi-chip-id=33,qmi-board-id=255`
  (125,288 bytes, from Windows' `bdwlan_qcc2072_1p0_ncm820A.elf`).
- The file the first-boot session parsed,
  `.work/tools/qcc2072-board-2.bin`, is the upstream container without that
  entry.
- When the lookup fails, ath12k brings up no interface at all (2026-09-26,
  before the HP data). A working `wlo1` shows that the lookup succeeded.
- `failed to get ACPI BDF EXT: -2` is the optional ACPI board-data
  extension and is harmless.

To confirm on the SSD install, run
`ls /lib/firmware/updates/ath12k/QCC2072/hw1.0/`. No re-extraction from
Windows is needed.

## Correction: the keyboard backlight is not a config change

The plan proposed enabling `ACPI_WMI` and `HP_WMI`. In qcom-next, both are
impossible on arm64:

- `ACPI_WMI` (`drivers/platform/wmi/Kconfig`) `depends on ACPI && X86`.
- `HP_WMI` lives under `drivers/platform/x86` and needs an ACPI EC
  (`ACPI_EC`). This laptop's EC is on I²C (IC10), not `PNP0C09`.

Windows binds three WMI mappers (`PNP0C14` with UIDs `0`, `H19P` and
`HWMI`), HP's `HPIC0003` "HP Application Driver" and `HPIC0005` "HP Mute
LED". How the keyboard backlight is actually controlled (by the EC on its
own, or through `HWMI` methods) is still open. Next step: decode `HWMI._WDG`
and search the EC AML for the backlight command.

## Bluetooth: the path is a GENI UART, like the I²C buses

Windows binds `QCOM0F6B` (`BTH0`) to "Qualcomm(R) Bluetooth UART Transport
Driver" (`QcBluetooth`). `QCOM0FEA` is "Aqstic BT ACX Transport", which is BT
audio offload and not needed for basic Bluetooth. From the DSDT:

- `BTH0._CRS` has two resources:
    - `UartSerialBus` on `\_SB.UR15`: 115200 baud initially, 8N1,
      RTS/CTS flow control, 32-byte FIFOs;
    - `GpioIo` output on `\_SB.GIO0`, pin `0x74` (GPIO 116, a direct TLMM
      pin). This is the Bluetooth enable line.
- `_DEP` lists `PEP0`, `PMIC`, `GLNK` and `UR15`. `_DSM` UUID
  `07be7e46-…` answers the NVM name ("default") and similar queries.
- `UR15` is `QCOM0F16`, "QUP_1_SE_6,4W,DP", at `0xA98000` (0x4000 bytes).
  It has one interrupt and a `GpioInt` on PDC pin 832, likely the RX wake
  line. `_STA` returns `0x0B`. `UARD`, also `QCOM0F16` ("QUP_2_SE_5,DBG"),
  is the debug UART.

In qcom-next:

- `btqca`/`hci_qca` support `QCA_QCC2072`, with no regulators in its SoC
  data.
- `SERIAL_QCOM_GENI`, `SERIAL_DEV_BUS` and `BT_HCIUART_QCA` are built in.
- `hci_qca` has an ACPI match table, for other chips only.

The gaps:

1. `qcom_geni_serial` has no ACPI support. It needs the same kind of
   firmware-owned `QCOM0F16` path that `QCOM0F10` got for I²C.
2. The baud clock. `hci_qca` switches to a 3 Mbaud operating speed. With no
   Linux clock provider under ACPI, that works only if the serial clock
   firmware left divides to 3 Mbaud.
3. GPIO 116 must be driven. The interim GPIO driver is read-only by design,
   so `hci_qca`'s `enable` GPIO request, which on ACPI falls back to
   `BTH0`'s `GpioIo`, would fail.
4. An ACPI match for `QCOM0F6B` with the QCC2072 SoC data in `hci_qca`.

Gaps 2 and 3 depend on what firmware left, so the next step is a read-only
snapshot. `scripts/linux/qcom0f16-snapshot/` binds nothing and writes
nothing. It records, for `UR15` and `UARD`:

- the SE protocol;
- the serial clock enable and divider;
- the UART word, parity and stop configuration;
- FIFO/DMA mode;
- GPIO 116's mux, direction and level.

The module is built against `7.3.0-rc2-glymur` and staged on the USB's FAT
partition at `glymur-tools/qcom0f16-snapshot/`. Run it on the SSD install
with `sudo bash run-snapshot.sh <that directory>`.

## Audio: SoundWire SDCA behind LPASS, confirmed live

These are present and bound under Windows on this unit, not just candidates
from HP's SoftPaqs:

- `SOUNDWIRE\SDCA_PERIPHERAL_10&MAN_0217&PART_0110` (SoundWire Audio
  Multifunction Device);
- SDCA functions `FUNC_0003` (type 08, with dynamic speaker and
  microphone endpoints) and `FUNC_0001` (type 0A, SoundWire HID);
- the `SdcaAggregator`;
- the endpoints "Speakers" and "Microphone Array" on "Qualcomm(R) Aqstic(TM)
  ACX Static Endpoints Audio Device".

The SoundWire master sits in the LPASS/ADSP domain, so audio follows the
remoteproc/DT path, like battery and USB-C. `QCOM1044` from the SoftPaq
analysis is not in the live PnP tree.

## USB-C and PMIC GLink

Windows binds `QCOM0F8E` ("Power Management PMIC GLink Device"),
`QCOM0F84` ("Shared Memory Port Device", GLink), `QCOM0F9D` ("USB Type-C
Device", UCSI) and `USBC000` (UCM-UCSI). This confirms that USB-C, battery,
AC and the RTC all hang off the ADSP GLink channel. Under Linux, `USBC000`
reads `_STA` 0 until `PMGK.LKUP` is set.

## Revised order

1. Bluetooth: take the UART snapshot. Then write the firmware-owned
   `QCOM0F16` serial support, the `hci_qca` ACPI match and a narrow
   BT_EN output path. This is the same pattern as I²C and needs no DT.
2. Keyboard backlight: find the real control path (EC or `HWMI`) before
   planning any code.
3. GPU, audio, USB-C, battery, AC and the RTC: device-tree/remoteproc path,
   as in the plan (battery last).
