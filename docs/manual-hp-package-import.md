# Manual HP Package Import Workflow

1. Open the official HP page in a normal browser:
   https://support.hp.com/in-en/drivers/hp-omnibook-5-16-inch-laptop-next-gen-ai-pc-16-bf1000/2103480507

2. Select:
   Windows 11 version 26H1 on ARM (64-bit) (if HP asks for OS)

3. Download:
   `Qualcomm Driver Pack`

4. Do NOT run it.

5. Place the downloaded file in:
   `.work/hp-software/incoming/`

6. Run:
   ```bash
   ./scripts/linux/import-hp-package.sh \
       --local .work/hp-software/incoming/<downloaded-file> \
       --title "Qualcomm Driver Pack" \
       --scope FAMILY
   ```

7. The script performs static extraction/analysis only.

8. Review generated metadata before promoting it into tracked TSV files.

## Future Discovery
Once the Qualcomm pack is imported, we specifically intend to discover:
- package identity/version
- supported platform IDs
- INF inventory
- ACPI IDs
- PCI IDs
- USB IDs
- HID IDs
- Qualcomm platform services
- ADSP firmware
- CDSP firmware
- SoCCP firmware
- GPU/GMU firmware
- WLAN firmware/IDs
- Bluetooth firmware/IDs
- audio hardware IDs/topology
- Type-C/UCSI devices
- PCIe platform drivers
- sensor/power services
- any literal GLYMUR/X2 strings
