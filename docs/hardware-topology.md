# Hardware Topology

This document describes the physical architecture of the HP OmniBook 5 16-bf1xxx family based on the HP Maintenance and Service Guide (P39932-002) and User Guide (P39931-002).

## System Board
- **DOCUMENTED**: Qualcomm Snapdragon X2 Elite X2E-84-100 processor option exists with 32 GB LPDDR5X-8448 dual-channel onboard memory (Service part number: Q02174-601).
- **TARGET-CONFIGURATION**: Match confirmed (X2E-84-100, 32GB RAM).

## Display Assembly
- **DOCUMENTED**: 16.0 inch WUXGA (1920 × 1200) OLED, low blue light, bent panel, BrightView, DCI-P3 95%, eDP 1.2 without PSR, 300 nits, 60 Hz, DBTS (Touch).
- **DOCUMENTED**: Display uses a specific display panel cable with a 4-pin connector at the bottom of the OLED panel.
- **TARGET-CONFIGURATION**: 16-inch OLED touchscreen.

## Camera
- **DOCUMENTED**: HP True Vision FHD Camera (USB2 based), with indicator LED, 1x infrared (IR) LED, f2.0, HD BSI sensor, WDR/TNR, 80° NFOV.

## WLAN Module
- **DOCUMENTED**: Removable M.2 2230 slot.
- **DOCUMENTED**: Options include Qualcomm Wi-Fi 7 FastConnect C7700 + Bluetooth 6.0 (P59089-005) or Qualcomm FastConnect 6900 Wi-Fi 6E + Bluetooth 5.3 WW WLAN (P13807-005).
- **TARGET-CONFIGURATION**: UNKNOWN (Specific module to be verified on target).

## Input Devices
- **DOCUMENTED**: Keyboard daughterboard is present (Part P48630-601 for X2 Plus/Elite processor units).
- **DOCUMENTED**: Touchpad is a Precision Clickpad with an image sensor.

## Storage
- **DOCUMENTED**: M.2 2280 PCIe NVMe.
- **TARGET-CONFIGURATION**: Installed, specific model UNKNOWN.

## Auxiliary Boards
- **DOCUMENTED**: USB/audio board connected via dedicated cable.

## Battery
- **DOCUMENTED**: 3-cell 59 Wh battery.
