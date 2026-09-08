# Linux on HP OmniBook 5 Glymur

This repository tracks native Linux bring-up for the HP OmniBook 5 16-bf1xxx family using Qualcomm Snapdragon X2 / Glymur.

The current target is:

    HP OmniBook 5 NGAI 16-bf1107nr
    D3ZN3UA
    Snapdragon X2 Elite X2E-84-100
    32 GB RAM
    16-inch OLED touchscreen

16-bf1107nr is the specific retail target.
16-bf1xxx is the HP hardware family covered by the service documentation.

The expected eventual DTS filename is:

    glymur-hp-omnibook-5-bf1xxx.dts

## Project Philosophy

- Evidence-first bring-up
- No foreign DTB will be booted on the target
- Other Glymur device trees may be studied as references only
- Machine-specific properties must be derived from the target machine or applicable documentation
- Unknown values must remain unknown rather than being guessed

Current phase: repository setup; target hardware has not yet arrived.

## PRE-ARRIVAL DEVELOPMENT FREEZE
The Linux build environment, upstream reference research, HP software archaeology, and Day-0 evidence tooling are prepared. No further target topology should be inferred before the physical HP OmniBook 5 16-bf1107nr arrives.

## NEXT PHASE
Phase 5 begins with physical inspection, BIOS documentation, and `day0-capture.ps1 -Preflight` on the factory Windows installation. No Linux boot should be attempted before the Day-0 capture is reviewed.
