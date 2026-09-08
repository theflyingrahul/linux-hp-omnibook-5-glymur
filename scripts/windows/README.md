# Windows Day-0 Capture Scripts

**DEVELOPMENT STATUS: prepared and statically tested; target execution pending hardware arrival.**

These scripts perform a read-only metadata snapshot of the factory Windows environment. They do NOT install software, modify registry, change drivers, or alter UEFI variables.

## Prerequisites
- Windows PowerShell 5.1 (No PowerShell Core / 7 required)
- Administrator privileges (recommended for ACPI, Power, and Registry capture)
- Offline execution is fully supported and recommended.

## Usage (Preflight)
Run this first to verify compatibility and free space without changing anything:
```powershell
.\day0-capture.ps1 -Preflight -OutputPath E:\day0-metadata
```

## Usage (Pass 1)
```powershell
.\day0-capture.ps1 -OutputPath E:\day0-metadata
```

## Usage (Pass 2 - Firmware/Driver Preservation)
```powershell
.\day0-capture.ps1 -OutputPath E:\day0-preservation -ExportDrivers -CopyFirmware
```

**Note:** The generated output may contain sensitive serials or proprietary blobs. Keep it secure and do not commit it to public version control.
