OBSERVED
    Directly observed or captured from the target HP OmniBook 5 16-bf1107nr.

HP-DOCUMENTED
    Explicitly documented by HP for the applicable 16-bf1xxx family.

UPSTREAM-REFERENCE
    Information from another Linux-supported Glymur machine, used only as a structural or implementation reference.

HP-SOFTWARE
    Information derived from a driver, firmware, BIOS, utility, or software package that HP publicly associates with the target SKU or applicable product family.
    HP-SOFTWARE evidence can establish that HP distributes support for a component or hardware ID for this SKU/family, but it does not by itself prove that a particular optional component is physically installed in the target unit.

INFERRED
    Reasoned from evidence but not directly confirmed.

UNKNOWN
    Not yet established.

Future DTS notes and hardware documentation should distinguish these categories.

## Evidence Semantics Examples

| Observation | Classification | What may be concluded |
|---|---|---|
| wlanfw20.mbn exists | OBSERVED-SOFTWARE | C7700-associated firmware package is present |
| DEV_1107 exists | OBSERVED-HARDWARE | Matching PCI device is physically enumerated |
| DEV_1107 + HP INF | OBSERVED-HARDWARE + HP-SOFTWARE | C7700/WCN785x identity strongly corroborated |
| DEV_1107 parent PCI path | OBSERVED-HARDWARE | Host routing evidence is available |
| only C7700 SoftPaq support | HP-SOFTWARE | HP distributes support; hardware presence unknown |
