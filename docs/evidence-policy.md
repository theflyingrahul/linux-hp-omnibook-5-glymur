# Evidence Policy

## Evidence Classifications

### Primary Evidence Tiers

OBSERVED-HARDWARE
    A physical device, PnP hardware ID, ACPI identity, or topology relationship
    directly enumerated or captured from the target HP OmniBook 5 16-bf1107nr.
    Example: PCI\VEN_17CB&DEV_1107 present in PnP device enumeration.

OBSERVED-SOFTWARE
    A firmware file, driver package, or software artifact observed on the target
    machine's factory Windows installation (e.g., DriverStore, installed drivers).
    Does NOT by itself prove that the corresponding physical hardware is installed.
    Example: wlanfw20.mbn present in C:\Windows\System32\DriverStore.

HP-DOCUMENTED
    Explicitly documented by HP for the applicable 16-bf1xxx family or specific
    SKU, through product specification pages, service manuals, or official support.
    Example: "Qualcomm Snapdragon X2 Elite" listed on the product page.

HP-SOFTWARE
    Information derived from a driver, firmware, BIOS, utility, or software package
    that HP publicly associates with the target SKU or applicable product family.
    HP-SOFTWARE evidence can establish that HP distributes support for a component
    or hardware ID for this SKU/family, but it does not by itself prove that a
    particular optional component is physically installed in the target unit.
    Example: sp173974.exe Qualcomm Driver Pack available for 16-bf1000 family.

UPSTREAM-REFERENCE
    Information from another Linux-supported Glymur machine, used only as a
    structural or implementation reference. Values must never be copied directly.
    Example: EliteBook X G2q uses pcie5 for NVMe.

INFERRED
    Reasoned from evidence but not directly confirmed. Must state the basis.
    Example: "WLAN likely on pcie4 based on ACPI _ADR and reference comparison."

UNKNOWN
    Not yet established.

### Derived / Compound Classifications

CORROBORATED MATCH
    An agreement between independent evidence sources — specifically when an
    OBSERVED-HARDWARE ID aligns with OBSERVED-SOFTWARE or HP-SOFTWARE.
    Example: PCI\VEN_17CB&DEV_1107 (OBSERVED-HARDWARE) + wlanfw20.mbn (OBSERVED-SOFTWARE)
    = FastConnect C7700/WCN785x strongly corroborated.

SOFTWARE-ONLY
    HP-SOFTWARE or OBSERVED-SOFTWARE evidence exists, but no OBSERVED-HARDWARE
    ID has been captured to confirm the component is physically present.

### DTS Property Classifications (used in glymur-reference-comparison.md)

BOARD-SPECIFIC
    A DTS property that varies between Glymur boards and must be determined
    per-target from hardware evidence.

SOC-COMMON
    A DTS property common to all Glymur (X2 Elite) boards, derived from SoC
    documentation or shared platform code.

COMPONENT-SPECIFIC
    A DTS property that depends on the specific component variant installed.

CHASSIS-SPECIFIC
    A DTS property related to the physical chassis (thermals, LEDs, buttons).

## Rules

1. Factory firmware file presence (OBSERVED-SOFTWARE) does NOT prove physical
   hardware presence (OBSERVED-HARDWARE).
2. PnP hardware presence (OBSERVED-HARDWARE) does NOT prove full board routing
   knowledge (PCIe root path, GPIO assignments, I2C bus/address).
3. UPSTREAM-REFERENCE values must never be copied into target DTS without
   independent target evidence.
4. Only use CORROBORATED MATCH when OBSERVED-HARDWARE and independent software
   evidence align.

## Evidence Semantics Examples

| Observation | Classification | What may be concluded |
|---|---|---|
| wlanfw20.mbn in DriverStore | OBSERVED-SOFTWARE | C7700-associated firmware package is present |
| DEV_1107 in PnP enumeration | OBSERVED-HARDWARE | Matching PCI device is physically enumerated |
| DEV_1107 + HP INF + wlanfw20.mbn | CORROBORATED MATCH | C7700/WCN785x identity strongly corroborated |
| DEV_1107 parent PCI path | OBSERVED-HARDWARE | Host routing evidence is available |
| Only C7700 SoftPaq in HP package | HP-SOFTWARE | HP distributes support; hardware presence unknown |
| EliteBook uses pcie5 for NVMe | UPSTREAM-REFERENCE | Reference only — target may differ |

Future DTS notes and hardware documentation should use these categories consistently.
