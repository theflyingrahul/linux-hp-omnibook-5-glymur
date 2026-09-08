# Glymur Reference Comparison

Research snapshot: 2026-09-08 11:34 UTC

## Reference Tree Availability

- **Qualcomm Glymur CRD**: Merged in Linus's tree (`glymur-crd.dts`).
- **HP EliteBook X G2q**: Actual source v5 retrieved from `lkml.iu.edu` (Applied to maintainer tree).
- **HP OmniBook Ultra 14-kg0xxx**: Actual source v1 retrieved from `lkml.iu.edu` (Under review).

## Comparison Table (Actual Source)

| Subsystem / property | Glymur CRD | HP EliteBook X G2q | HP OmniBook Ultra | Classification |
|---|---|---|---|---|
| **Root/Model** | `Qualcomm Technologies, Inc. Glymur CRD` | `HP EliteBook X G2q 14 AI` | `HP OmniBook Ultra 14-kg0xxx` | BOARD-SPECIFIC |
| **Compatible** | `qcom,glymur-crd`, `qcom,glymur` | `hp,elitebook-x-g2q`, `qcom,glymur` | `hp,omnibook-ultra-kg0xxx`, `qcom,glymur` | BOARD-SPECIFIC |
| **Reserved Memory** | Defined in `glymur.dtsi` | Inherited | Inherited | SOC-COMMON |
| **PCIe Root (NVMe)** | UNKNOWN | `pcie5` | `pcie3b` | BOARD-SPECIFIC |
| **PCIe Root (WLAN)** | UNKNOWN | `pcie4` | `pcie4` | COMPONENT-SPECIFIC |
| **Internal Display** | `mdss_dp0` / `mdss_dp1` generic | `samsung,atna33xc20` eDP | Generic 2880x1800 eDP | COMPONENT-SPECIFIC |
| **USB-C Ports** | UNKNOWN | 2 Type-C ports (`usb_0`, `usb_1`) | 3 Type-C ports (`usb_0`, `usb_1`, `usb_2`) | CHASSIS-SPECIFIC |
| **USB-A Host** | UNKNOWN | `usb_mp` (multiport) | None apparent | CHASSIS-SPECIFIC |
| **USB HS PHY** | UNKNOWN | `usb_hs_phy` | `usb_hs_phy` (Redriver missing/questioned) | CHASSIS-SPECIFIC |
| **I2C HID Buses** | UNKNOWN | `i2c0`, `i2c8` | `i2c0`, `i2c4`, `i2c8` | CHASSIS-SPECIFIC |
| **Audio Topology** | `GLYMUR-CRD` | `HP EliteBook X G2q 14 AI` | `GLYMUR-CRD` (Questioned by reviewer) | CHASSIS-SPECIFIC |
| **Speakers** | UNKNOWN | Woofer/Tweeter Left/Right | Woofer/Tweeter Left/Right | COMPONENT-SPECIFIC |
| **Remoteproc CDSP** | `qcom,glymur-cdsp-pas` | Inherited | Inherited | SOC-COMMON |
| **Firmware Names** | UNKNOWN | `hp/elitebook-x-g2q/qccdsp8480.mbn` | `hp/omnibook-ultra-14-kg0xxx/qccdsp8480.mbn` | BOARD-SPECIFIC |
| **GPIO Reserved Ranges** | None | `<4 4>` (EC TZ Secure I3C) | `<4 4>` (Questioned by reviewer) | CHASSIS-SPECIFIC |

## Upstream Review Lessons for the OmniBook 5 Bring-up

1. **Remoteproc SoCCP Redundancy:** Abel Vesa explicitly rejected overriding `&remoteproc_soccp { status = "okay"; }` in the OmniBook Ultra patch because it is already enabled in the generic `glymur.dtsi`. The OmniBook 5 DTS must not redefine generic SoC defaults.
2. **GPU / GMU Redundancy:** Similar to SoCCP, the GPU and GMU nodes are generically enabled upstream. Do not override their status in the board DTS unless strictly necessary.
3. **Audio Model Name:** The OmniBook Ultra v1 reused the `GLYMUR-CRD` sound model/topology; review requested a board-specific model name instead. Do not copy a CRD or another OEM sound model/topology name for the OmniBook 5. The board-specific audio topology must be established from the target hardware and supporting firmware/configuration.
4. **GPIO Reserved Ranges:** Reserved GPIO ranges must have a known, defensible purpose. A comment documents evidence; it does not substitute for evidence. Although EliteBook documents `<4 4>` as `EC TZ Secure I3C`, this must NOT be treated as evidence that the OmniBook 5 uses the same range.
5. **USB Redrivers:** Abel Vesa questioned the omission of a redriver for `usb_hs_phy` on the OmniBook Ultra. We must carefully map the physical USB PHYs to redrivers/retimers for the OmniBook 5.
6. **HDMI / Combo PHY issues:** The EliteBook v5 patch dropped chassis HDMI support because the `usb_2` combo PHY failed to operate in a DisplayPort-only configuration on Glymur (a known issue also affecting ASUS Zenbook). We should be cautious if the OmniBook 5 attempts a similar display output configuration.

## DO NOT COPY THESE VALUES

Because the actual upstream patches for the **HP EliteBook X G2q** and **HP OmniBook Ultra 14-kg0xxx** differ structurally, we cannot inherit reference defaults. **Similar component identity does not imply identical bus routing.**

The reference values below are examples of board-specific implementation, not candidate defaults for the OmniBook 5:

- **NVMe PCIe controller:** EliteBook uses `pcie5`, OmniBook uses `pcie3b`.
- **WLAN PCIe controller:** Both use `pcie4`, but this must still be verified for the target chassis.
- **I2C bus assignment:** EliteBook uses `i2c0` and `i2c8`; OmniBook uses `i2c0`, `i2c4`, and `i2c8`.
- **HID device addresses / HID IRQ GPIOs:** Touchpad, touchscreen, and keyboard addresses differ depending on the IC and wiring.
- **GPIO polarity / wake GPIOs:** Lid switches and wake lines are heavily board-specific.
- **GPIO reserved ranges:** Do not blindly reserve ranges like `<4 4>`.
- **PMIC rails / regulator voltages / consumers:** Power routing varies by motherboard schematic. Do not guess voltage parameters.
- **USB-C connector indexes / USB controller mapping:** EliteBook has 2 ports and `usb_mp`; OmniBook has 3 ports and no `usb_mp`.
- **HS PHY / QMP PHY mapping / eUSB2 / DisplayPort routing:** The physical topology to the Type-C port must be mapped via ACPI.
- **Panel reset / power sequencing:** eDP panels have unique timing and GPIO requirements.
- **Audio model/topology:** The name must precisely match firmware provided in `linux-firmware`.
- **Firmware names:** Path structures explicitly include the OEM model name.

## Board Support Summaries

**Glymur CRD**
- Reference baseline for Qualcomm.

**HP EliteBook X G2q**
- Latest revision: v5 (2026-08-29)
- Status: Partially Applied (Maintainer Tree)

**HP OmniBook Ultra 14-kg0xxx**
- Latest revision: v1 (2026-08-30)
- Status: Under review (Received substantive review comments; no maintainer tree application located).
