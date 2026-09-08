# Day-0 Evidence Requirements

The goal of this document is to establish a strict evidence gate before writing any device tree (DTS) code for the **HP OmniBook 5 16-bf1107nr**. 

## DO NOT COPY THESE VALUES

Because the actual upstream patches for the **HP EliteBook X G2q** and **HP OmniBook Ultra 14-kg0xxx** differ structurally, we cannot inherit reference defaults. **Similar component identity does not imply identical bus routing.**

The reference values observed in upstream patches are examples of board-specific implementation, not candidate defaults for the OmniBook 5. The following values **must not be copied** and must be independently verified on the target:

1. **NVMe PCIe Controller**
2. **WLAN PCIe Controller**
3. **I2C Bus Assignments**
4. **HID Device Addresses and IRQ GPIOs**
5. **GPIO Polarity and Wake GPIOs**
6. **GPIO Reserved Ranges**
7. **PMIC Rails, Regulator Voltages, and Consumers**
8. **USB-C Connector Indexes and USB Controller Mapping**
9. **HS PHY / QMP PHY Mapping and eUSB2 Repeater/Redriver Topology**
10. **DisplayPort Routing**
11. **Panel Reset and Power Sequencing**
12. **Audio Model and Topology**
13. **Firmware Names**

---

## Minimum Validation Gate

No `glymur-hp-omnibook-5-bf1xxx.dts` file may be committed to this repository until the following questions are securely documented via target hardware observation:

### PCIe and Storage
- **Question:** Which specific PCIe root port does the OmniBook 5 use for its NVMe SSD?
- **Question:** Which PCIe root port is assigned to the FastConnect WLAN module?

### I2C and HID (Keyboard, Touchpad, Touchscreen)
- **Question:** Which I2C buses correspond to the Keyboard, Clickpad, and Touchscreen, and what are their ACPI `_CRS` payload addresses?

### USB Topology and Type-C
- **Question:** For each of the two physical USB-C ports, which USB controller, HS PHY, SS/QMP PHY, PMIC-GLINK connector index, eUSB2 repeater/redriver, and DisplayPort path serve it?
  *(Note: Physical USB-C port count: 2. Evidence: HP-DOCUMENTED)*
- **Question:** Is the chassis USB-A port wired to the `usb_mp` controller?
- **Question:** Are there I2C-controlled USB redrivers or retimers required for the USB-C DP outputs?

### Firmware and Audio
- **Question:** What are the exact ADSP, CDSP, and GPU firmware names stored in the Windows DriverStore for the `16-bf1xxx` platform?
- **Question:** What are the specific Codec IDs and speaker routing names for the audio topology?

### GPIO and PMIC
- **Question:** Which TLMM GPIO ranges, if any, are reserved from Linux on the OmniBook 5, and what firmware or hardware owns each range?
- **Question:** What are the exact voltage parameters and always-on requirements for the PMIC regulators?

## High-Priority Day-0 Artifacts: Windows DriverStore

The public HP support page exposes very few drivers for manual download. Therefore, **capturing the factory Windows DriverStore is a P0/P1 Day-0 requirement**. The factory image and Windows Update may contain drivers/firmware not separately exposed on HP's public support page.

We will need, at minimum:
- installed OEM INF inventory
- provider
- driver version
- driver date
- hardware IDs
- compatible IDs
- device instance IDs
- installed service names
- package directories
- firmware referenced by each package
- package provenance where Windows exposes it

*Note: The capture commands are not yet written. They will be formulated once the Day-0 data capture scripts are initialized.*
