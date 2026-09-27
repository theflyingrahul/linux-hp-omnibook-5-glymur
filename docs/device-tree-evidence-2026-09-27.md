# HP OmniBook 5 16-bf1xxx Device Tree: Evidence, September 27, 2026

The owner chose the device-tree route (GPU, audio, USB-C, battery and
Bluetooth need it). The HP DTS lives in `dts/qcom/`:

- `glymur-hp-omnibook-5-bf1xxx.dtsi`: the shared board description;
- `glymur-hp-omnibook-5-bf1xxx-minimal.dts`: storage, input, lid, Wi-Fi and
  Bluetooth on the firmware framebuffer, as a fallback;
- `glymur-hp-omnibook-5-bf1xxx.dts` (full): adds the eDP OLED, GPU,
  ADSP/CDSP and PMIC GLink.

It is written for this machine, not copied from another board. Qualcomm's
`glymur.dtsi` describes the SoC. Every board value below comes from this
laptop. The Glymur CRD and the ASUS Zenbook A16 DTS served only as a
checklist of which board decisions a laptop needs.

## Which SoC description

| Question | Evidence | Result |
|---|---|---|
| Glymur or Mahua die? | DSDT `SOID` 0x2B5, `SIDS` "X2E84100", JTAG `0x1021E0E1` (no kernel tree maps ID 693). HP's PEP recipes drive GPIO 144, whose only function is `pcie3a_clk` (Glymur; Mahua deletes PCIe 3a), and GPIO 156, `pcie3b_clk` | Glymur (`glymur.dtsi`). The PEP tables could be shared across SKUs; a DT boot that brings up PCIe and the interconnect confirms it. |
| CPUs | MADT: 18 GICC entries, MPIDR 0x0-0x500 and 0x10000-0x10500 enabled, 0x20000-0x20500 disabled | Delete cluster 2 (`cpu12`-`17`, their power domains, `bwmon_cluster2`, `cpu-map` cluster 2 and its CPU thermal zones), as `mahua.dtsi` does. The compiled DTBs have 12 CPUs. |
| CPU types | CPUs 0-5 MIDR `0x512f0021`, 6-11 `0x511f0021` | Match `glymur.dtsi` (`oryon-2-2`, `oryon-2-1`) |
| GPU | Windows: "Adreno X2-85", `QCOM0FF5` rev 0x49 | `qcom,adreno-44070001` uses msm's `x285_protect`, `gen80100_sqe.fw` and `gen80100_gmu.bin` (in Ubuntu linux-firmware) |
| Reserved memory | Early memory node ranges of the ACPI boot | All 21 `reserved-memory` regions of `glymur.dtsi` fall inside firmware holes; none overlaps RAM |
| Root clocks | PEP votes PMK8850 ("A") buffers `CLK6_A`/`CLK7_A` | `xo_board` 38.4 MHz and `sleep_clk` 32 kHz, the PMIC's fixed outputs |

## Board devices

| Device | DT | HP evidence |
|---|---|---|
| Keyboard | `i2c0` (0xB80000) `hid-over-i2c` @0x3a, descriptor 0x1, IRQ GPIO 67 level-low | `ECKB` `QTEC0001` `_CRS` I2cSerialBus 0x3a/400 kHz on `I2C1`; GpioInt level-low wake pull-up PDC 704 → GPIO 67 (`analyze-acpi-pdc.py`); `_DSM` fn 1 → 1; PEP pins 0/1 |
| Touchpad | `i2c4` (0xB90000) @0x15, GPIO 3 | `TCPD` (`ELAN0189` because `SPID`=0) on `I2C5`; PDC 896 → GPIO 3; `_DSM` → 1; PEP 16/17 |
| Touchscreen | `i2c8` (0xA80000) @0x10, GPIO 51, no reset | `TSC1` `ELAN2513` (`SKID`=1) on `I2C9`; GpioInt GPIO 51; no GpioIo; PEP 32/33 |
| Lid | `gpio-keys` `SW_LID` GPIO 92 active-low | `LID0._LID` returns `GIO0.LIDR` = GPIO 92 level (1 = open); `LIGE` PDC 960 → GPIO 92 |
| NVMe | `pcie5`, CLKREQ# 153, PERST# 152, WAKE# 154 | PEP `PCI5` drives 153. 152/154 are unconfirmed and are checked by the snapshot module before booting. |
| Wi-Fi | `pcie4`, CLKREQ# 147, PERST# 146, WAKE# 148 | PEP `PCI4` drives 147. 146/148 are unconfirmed, as for NVMe. The module's 3.3 V (GPIO 94) and enables (116/117) stay as firmware left them. |
| Bluetooth | `uart14` (0xA98000) `qcom,qcc2072-bt`, `enable-gpios` GPIO 116, 3.2 Mbaud | `BTH0` `QCOM0F6B` UartSerialBus on `UR15` (`QCOM0F16`, QUP_1_SE_6); GpioIo 116; `qcbluetooth8480.inf` `BaudRate` 3200000; UART pins 56-59 from `BSRC_UART_4Wire_1.bin` |
| Panel | `mdss_dp3` + `samsung,atna33xc20`, enable GPIO 18, power GPIO 70 (fixed regulator), HPD GPIO 119 (`edp0_hot`) | EDID SDC 0x4214, "Integrated Monitor (ATNA60KJ02-0)", 1920x1200, 8 bpc, DisplayPort; PEP `GPU0` drives 18, 70 and 119 |
| ADSP/CDSP | `firmware-name` `qcom/glymur/HP/omnibook-5-16-bf1xxx/…` | HP driver pack `qcadsp8480.mbn`, `adsp_dtbs.elf`, `qccdsp8480.mbn`, `cdsp_dtbs.elf` (`boards/…/firmware`, installed by `glymur-ssd/install-firmware.sh`) |
| Battery/AC | `pmic-glink`, no connectors | ACPI `_BST`/`_PSR` via `\_SB.PMGK` (PMIC GLink on the ADSP) |

Other I²C devices, not in the DT yet:

- `i2c5` (`I2C6`, 0xB94000): `QCOM0FC6` @0x08 and SAR sensors `QCOM0F9E`
  @0x28 and `QCOM0F9F` @0x2C (GPIO 30/31). Unlike the Zenbook, there are no
  USB redrivers on it.
- `i2c9` (`IC10`): the EC `QCOM1007` @0x76. Linux has no driver for this
  EC; it runs the fan on its own.

## Safety choices

- **No RPMh regulators are declared.** Linux changes no PMIC rail, so every
  rail stays as firmware left it. PHY and TCSR drivers use dummy supplies
  through `devm_regulator_bulk_get()` (checked in `clk-ref.c` and
  `phy-qcom-qmp-pcie.c`). HP's PEP votes give the real rails, with values
  that match the Zenbook's rather than the CRD's, together with PMIC
  `H_E0`, which the Zenbook lacks. They come in a later stage.
- **GPIO allow-list.** `gpio-reserved-ranges` reserves every TLMM pin that
  the file does not use, so an unidentified EC reset or security pin can
  never be touched. The ranges are generated and checked by script.
    - Minimal: 0-1, 3, 16-17, 32-33, 51, 56-59, 67, 92, 116, 146-148,
      152-154.
    - Full adds 18, 70 and 119.
- **Fallbacks.** GRUB has the minimal DTB, both ACPI entries and the
  previous kernel.

## Validation

- Both DTBs compile with `W=1`. The only warning is in `glymur.dtsi`.
- `dtbs_check` (dtschema 2026.9) against the CRD baseline finds 25 issues
  of our own, all of known kinds:
    - required PHY/TCSR supplies, which follow from the no-regulator
      policy;
    - `enable-gpios` on `qcom,qcc2072-bt`, which the binding does not
      allow (it expects the WCN power sequencer), although the driver
      supports it;
    - the new board compatible, which needs a `qcom.yaml` entry before
      upstreaming;
    - the ADSP `iommus` length, which comes from `glymur.dtsi`.

## Open before the first DT boot

- Confirm PERST#/WAKE# 146/148/152/154 from firmware state with
  `scripts/linux/qcom0f16-snapshot` (a no-reboot run on the SSD install).
- Kernel `7.3.0-rc2-glymur-2` builds the DT path in: GCC, TCSR,
  pinctrl-glymur, interconnect and the QMP PCIe PHY, so no initramfs is
  needed. The same kernel still boots ACPI.
