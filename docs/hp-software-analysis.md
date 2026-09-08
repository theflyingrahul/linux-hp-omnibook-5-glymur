# HP Software Archaeology Analysis

**Target SKU:** HP OmniBook 5 NGAI 16-bf1107nr (Product number: D3ZN3UA)
**Hardware Platform:** Qualcomm Snapdragon X2 Elite (Glymur)

## Phase 3.2 Status

Official family support page:
    IDENTIFIED

Qualcomm Driver Pack:
    IDENTIFIED BY HUMAN SUPPORT-PAGE INSPECTION

SoftPaq:
    UNKNOWN

Direct URL:
    UNKNOWN

Package binary:
    NOT YET IMPORTED

Static package analysis:
    PENDING

Required external action:
    manually download one Qualcomm Driver Pack file

*Note: The 16-bf1000 / D3ZN3UA entries were not located in the HP enterprise SCCM catalog examined during Phase 3.*

## Official Sources

Official HP driver page:
https://support.hp.com/in-en/drivers/hp-omnibook-5-16-inch-laptop-next-gen-ai-pc-16-bf1000/2103480507

HP support-page product identifier:
2103480507

Product family:
HP OmniBook 5 16 inch Laptop Next Gen AI PC 16-bf1000

Source:
human-verified official HP support page

Evidence:
HP-SOFTWARE / FAMILY

## Subsystem Matrix

| Component | Candidate Hardware ID | Firmware Artifacts | Confidence | Evidence Source | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **WLAN** | | | | HP-SOFTWARE | |
| **Bluetooth** | | | | HP-SOFTWARE | |
| **Audio DSP** | | | | HP-SOFTWARE | |
| **Audio Amp/Codec** | | | | HP-SOFTWARE | |
| **Sensors** | | | | HP-SOFTWARE | |
| **USB/Type-C** | | | | HP-SOFTWARE | |
| **Camera** | | | | HP-SOFTWARE | |
| **SoC Firmware** | | | | HP-SOFTWARE | |

## Contradictions / Observations
- HUMAN-VERIFIED: HP exposes a Qualcomm driver pack on the 16-bf1000 driver page.
- UNKNOWN: Which subsystems it contains.
- INFERRED POSSIBILITY: The package may aggregate multiple Qualcomm platform drivers, which could explain the small public package list.


## Software Evidence Sources
In this software-analysis documentation we distinguish between three sources of drivers and metadata:

1. **HP PUBLIC SUPPORT PAGE**: What HP exposes for manual download (such as the Qualcomm Driver Pack).
2. **FACTORY WINDOWS IMAGE**: What is preinstalled on the physical machine.
3. **WINDOWS UPDATE / MICROSOFT DRIVER DELIVERY**: Additional packages that may be installed or updated automatically by the OS.

*These sets are not assumed to be identical. Day 0 will capture the factory image (Source 2). Later comparisons may determine which components originated from the public support page (Source 1).*
