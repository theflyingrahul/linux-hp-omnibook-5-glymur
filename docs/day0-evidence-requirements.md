# Day-0 Evidence Requirements

| Evidence requirement | Capture source | Automated | Priority | Notes |
|---|---|---|---|---|
| Complete PnP Inventory | `Get-PnpDevice`, `pnputil` | Yes | P0 | Resolves WLAN, Touch, Audio, Camera IDs |
| ACPI Registry Dump | `HKLM\HARDWARE\ACPI` | Yes | P0 | Fallback if `acpidump` is absent |
| ACPI Tables | `acpidump.exe` | Optional | P0 | Highly recommended optional tool |
| SMBIOS Identity | `Win32_ComputerSystemProduct` | Yes | P0 | Validates D3ZN3UA / SKUs |
| Display EDID | Registry (`DISPLAY\...\EDID`) | Yes | P1 | Identifies OLED panel |
| Storage NVMe Path | `pnputil` relations | Yes | P0 | Finds which PCIe root port hosts NVMe |
| USB-C Topology | `pnputil` / USB enumeration | Yes | P1 | Correlates UCSI to physical ports |
| Factory Firmware Blobs| DriverStore scanning | Yes | P0 | Matches against HP-SOFTWARE candidates |

## Evidence that may still require Linux/UEFI experimentation
- Exact regulator topology and internal PMIC relationships.
- Physical Type-C DisplayPort alternate mode electrical routing.
- GPIO numbers not explicitly detailed in ACPI.
- Firmware ownership of reserved GPIO ranges (e.g., ADSP).
- Panel power sequencing delays.
