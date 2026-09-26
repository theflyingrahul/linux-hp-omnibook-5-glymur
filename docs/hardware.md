# Target Hardware

| Subsystem | Known information | Evidence | Notes |
|---|---|---|---|
| Product family | HP OmniBook 5 16 inch Laptop Next Gen AI PC<br>16-bf1xxx | HP-DOCUMENTED | |
| Target SKU | HP OmniBook 5 NGAI 16-bf1107nr<br>D3ZN3UA#ABA | OBSERVED-UEFI | BIOS Main page shows the product number; serial/UUID fields remain private |
| SoC | Qualcomm Snapdragon X2 Elite X2E-84-100 | HP-DOCUMENTED | |
| Memory | 32 GB<br>LPDDR5X-8448<br>onboard, not upgradeable | HP-DOCUMENTED | |
| GPU | Qualcomm Adreno integrated graphics | HP-DOCUMENTED | |
| Storage interface | PCIe NVMe<br>M.2 2280 | HP-DOCUMENTED | |
| Display family | 16 inch<br>OLED<br>eDP<br>touchscreen target | HP-DOCUMENTED | |
| Battery family | 3-cell<br>59 Wh | HP-DOCUMENTED | |
| Ports | 1x USB Type-A<br>2x USB Type-C<br>audio combo jack | OBSERVED-HARDWARE + HP-DOCUMENTED | Port arrangement corroborated by private photographs; Linux routing remains unknown |
| Camera | HP True Vision FHD Camera<br>USB2, IR LED, 1080p | HP-DOCUMENTED | Manual p.48 |
| Touchpad | Precision Clickpad with image sensor | HP-DOCUMENTED | Manual p.47 |
| Keyboard | Connected via keyboard daughterboard | HP-DOCUMENTED | Part P48630-601 |

HP service manual documentation lists:
- Qualcomm FastConnect C7700 Wi-Fi 7 + Bluetooth 6.0
- Qualcomm FastConnect 6900 Wi-Fi 6E + Bluetooth 5.3
Evidence: HP-DOCUMENTED

Target product specification lists:
- Qualcomm FastConnect C7700 Wi-Fi 7 + Bluetooth 6.0
Evidence: HP-DOCUMENTED

Physical target observation (2026-09-14):
- **OBSERVED-HARDWARE / OBSERVED-UEFI**: Windows and BIOS identify `HP OmniBook 5 Laptop 16-bf1xxx`, family `HP OmniBook 5`, product number `D3ZN3UA#ABA`, baseboard `8F47`, BIOS `F.06`, ARM64, and approximately 32 GB RAM.
- **OBSERVED-HARDWARE**: Private photographs show two USB Type-C ports, one USB Type-A port, and an audio combo jack; the chassis remains unopened.
- **OBSERVED-HARDWARE**: Qualcomm FastConnect C7700 NCM820A Wi-Fi 7 adapter and matching Bluetooth adapter are present.
- **OBSERVED-HARDWARE**: HP True Vision FHD and IR camera functions, ELAN touchscreen/touchpad functions, and a Samsung NVMe device are present.
- **UNKNOWN**: Complete ACPI routing, Linux PCIe controller/node mapping, and Linux functionality remain unverified. Windows parent/root-port, curated ACPI evidence, and redacted manual-photo findings are recorded in `docs/day0-first-pass-2026-09-14.md` and `docs/acpi-evidence-review-2026-09-14.md`.
