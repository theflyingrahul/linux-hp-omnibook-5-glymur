<#
.SYNOPSIS
Day-0 Hardware Capture Tool for HP OmniBook 5 16-bf1xxx

.DESCRIPTION
Captures metadata, ACPI, PnP, and Driver information read-only.
This script must NOT modify system state.

.PARAMETER OutputPath
Required. Path to store the capture bundle.

.PARAMETER ExportDrivers
Optional. If specified, extracts signed drivers to private/drivers.

.PARAMETER CopyFirmware
Optional. If specified, copies candidate firmware blobs to private/firmware.

.PARAMETER AcpiToolsPath
Optional. Path containing acpidump.exe / iasl.exe.

.PARAMETER Verbose
Optional. Enables verbose logging.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [switch]$ExportDrivers,
    [switch]$CopyFirmware,

    [string]$AcpiToolsPath
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"
$SchemaVersion = 1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "helpers.ps1")

# Create structure
$publicDir = Join-Path $OutputPath "public"
$rawDir = Join-Path $OutputPath "raw"
$privateDir = Join-Path $OutputPath "private"
$logsDir = Join-Path $OutputPath "logs"

$dirsToCreate = @(
    $OutputPath,
    $publicDir, $rawDir, $privateDir, $logsDir,
    (Join-Path $publicDir "system"),
    (Join-Path $publicDir "hardware"),
    (Join-Path $publicDir "pnp"),
    (Join-Path $publicDir "drivers"),
    (Join-Path $publicDir "storage"),
    (Join-Path $publicDir "power"),
    (Join-Path $publicDir "network"),
    (Join-Path $publicDir "bluetooth"),
    (Join-Path $publicDir "audio"),
    (Join-Path $publicDir "camera"),
    (Join-Path $publicDir "input"),
    (Join-Path $publicDir "display"),
    (Join-Path $publicDir "usb"),
    (Join-Path $publicDir "firmware"),
    (Join-Path $rawDir "pnp"),
    (Join-Path $rawDir "acpi"),
    (Join-Path $rawDir "acpi\tables"),
    (Join-Path $rawDir "registry"),
    (Join-Path $rawDir "power"),
    (Join-Path $rawDir "display\edid"),
    (Join-Path $rawDir "firmware"),
    (Join-Path $rawDir "drivers\inf"),
    (Join-Path $rawDir "command-output"),
    (Join-Path $rawDir "uefi"),
    (Join-Path $privateDir "identity"),
    (Join-Path $privateDir "drivers"),
    (Join-Path $privateDir "firmware")
)

foreach ($d in $dirsToCreate) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

$global:CaptureLogPath = Join-Path $logsDir "capture.log"
$global:FailuresLogPath = Join-Path $logsDir "failures.log"

$elevated = Test-Elevated
Write-Log "Starting Day-0 Capture (Version $ScriptVersion)"
Write-Log "Elevated execution: $elevated"
if (-not $elevated) {
    Write-Log "WARNING: Running without Administrator privileges. Some captures (like ACPI tables or complete registry exports) may be skipped or incomplete." -Level "WARNING"
}

$SectionStatuses = @{}
$CaptureStart = (Get-Date).ToUniversalTime()

function Run-Section {
    param([string]$Name, [scriptblock]$Script)
    Write-Log "--- Starting Section: $Name ---"
    try {
        $status = & $Script
        if (-not $status) { $status = "PASS" }
        $SectionStatuses[$Name] = $status
        Write-Log "Section $Name finished with status: $status"
    } catch {
        Write-Log "Section $Name failed: $_" -Level "ERROR"
        $SectionStatuses[$Name] = "FAIL"
    }
}

# 1. Private Identity
Run-Section "Private Identity" {
    $csProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $idData = @{
        SystemSKUNumber = $csProduct.SKUNumber
        SMBIOSUUID = $csProduct.UUID
        BaseBoardSerial = $baseBoard.SerialNumber
        BIOSSerial = $bios.SerialNumber
        ComputerName = $cs.Name
    }
    Export-SafeJson -Data $idData -Path (Join-Path $privateDir "identity\identity.json")
    return "PASS"
}

# 2. SMBIOS / System (Public safe fields)
Run-Section "SMBIOS / System" {
    $csProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    
    $sysData = @{
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        SystemFamily = $cs.SystemFamily
        BaseBoardProduct = $baseBoard.Product
        BaseBoardVersion = $baseBoard.Version
        BIOSVersion = $bios.SMBIOSBIOSVersion
        BIOSDate = $bios.ReleaseDate
        OSBuild = $os.BuildNumber
        OSArchitecture = $os.OSArchitecture
        OSEdition = $os.Caption
    }
    Export-SafeJson -Data $sysData -Path (Join-Path $publicDir "system\system-info.json")
    
    Invoke-ExternalCommand -Command "systeminfo.exe" -ArgsList @() -OutFile (Join-Path $rawDir "command-output\systeminfo.txt") | Out-Null
    # msinfo32 /report is very slow and sometimes hangs. We'll skip it in default or run it asynchronously if needed, but per requirements we run it read-only.
    Write-Log "Invoking msinfo32 /report (this may take a moment)..."
    Invoke-ExternalCommand -Command "msinfo32.exe" -ArgsList @("/report", (Join-Path $rawDir "command-output\msinfo32.txt")) | Out-Null

    return "PASS"
}

# 3. Complete PnP Inventory
Run-Section "PnP Inventory" {
    $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
    Export-SafeTsv -Data $devices -Path (Join-Path $publicDir "pnp\devices.tsv")
    
    $allProps = @()
    foreach ($dev in $devices) {
        $props = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue
        foreach ($p in $props) {
            $allProps += @{
                InstanceId = $dev.InstanceId
                KeyName = $p.KeyName
                Data = $p.Data
                Type = $p.Type
            }
        }
    }
    Export-SafeJson -Data $allProps -Path (Join-Path $rawDir "pnp\all-properties.json")
    return "PASS"
}

# 4. PnPUtil Enumeration
Run-Section "PnPUtil Enumeration" {
    # Try rich enum
    $pnputilArgs = @("/enum-devices", "/connected", "/ids", "/relations", "/services", "/stack", "/drivers", "/interfaces", "/properties", "/resources")
    $res = Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList $pnputilArgs -OutFile (Join-Path $rawDir "command-output\pnputil-enum-devices-rich.txt")
    if ($res.ExitCode -ne 0) {
        Write-Log "Rich pnputil enum failed, falling back to basic." -Level "WARNING"
        Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/enum-devices", "/connected") -OutFile (Join-Path $rawDir "command-output\pnputil-enum-devices-basic.txt") | Out-Null
    }
    return "PASS"
}

# 5. Driver Inventory
Run-Section "Driver Inventory" {
    $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue
    Export-SafeTsv -Data $drivers -Path (Join-Path $publicDir "drivers\signed-drivers.tsv")
    
    Invoke-ExternalCommand -Command "driverquery.exe" -ArgsList @("/v", "/fo", "csv") -OutFile (Join-Path $rawDir "command-output\driverquery.csv") | Out-Null
    Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/enum-drivers") -OutFile (Join-Path $rawDir "command-output\pnputil-enum-drivers.txt") | Out-Null
    return "PASS"
}

# 6. Factory DriverStore Inventory
Run-Section "Factory DriverStore" {
    $dsPath = Join-Path $env:windir "System32\DriverStore\FileRepository"
    if (Test-Path $dsPath) {
        $files = Get-ChildItem -Path $dsPath -Recurse -File -ErrorAction SilentlyContinue
        $inventory = $files | Select-Object @{Name="RelativePath";Expression={$_.FullName.Substring($dsPath.Length+1)}}, Name, Extension, Length, LastWriteTime
        Export-SafeTsv -Data $inventory -Path (Join-Path $rawDir "firmware\driverstore-file-inventory.tsv")
        
        $candidates = @()
        $fwExts = @('.mbn','.elf','.melf','.bin','.fw','.bdf','.tlv','.jsn','.json','.dat','.cfg')
        foreach ($f in $files) {
            if ($fwExts -contains $f.Extension.ToLower()) {
                $candidates += @{
                    Filename = $f.Name
                    RelativePath = $f.FullName.Substring($dsPath.Length+1)
                    Size = $f.Length
                    SHA256 = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
                    SourcePackage = $f.Directory.Name
                }
            }
        }
        Export-SafeTsv -Data $candidates -Path (Join-Path $rawDir "firmware\candidates.tsv")
        
        if ($CopyFirmware) {
            foreach ($c in $candidates) {
                $targetPath = Join-Path $privateDir "firmware\$($c.SourcePackage)\$($c.Filename)"
                $targetDir = Split-Path $targetPath -Parent
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
                Copy-Item -Path (Join-Path $dsPath $c.RelativePath) -Destination $targetPath -ErrorAction SilentlyContinue
            }
        }
    }
    return "PASS"
}

# 7. ACPI Registry
Run-Section "ACPI Registry" {
    if ($elevated) {
        Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\HARDWARE\ACPI", (Join-Path $rawDir "registry\HKLM_HARDWARE_ACPI.reg"), "/y") | Out-Null
        Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_ACPI.reg"), "/y") | Out-Null
        Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\PCI", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_PCI.reg"), "/y") | Out-Null
        Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\USB", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_USB.reg"), "/y") | Out-Null
    } else {
        return "PARTIAL"
    }
    return "PASS"
}

# 8. ACPI Tools (Optional)
Run-Section "ACPI Tools" {
    $acpidump = ""
    if ($AcpiToolsPath) {
        $candidate = Join-Path $AcpiToolsPath "acpidump.exe"
        if (Test-Path $candidate) { $acpidump = $candidate }
    }
    if (-not $acpidump) {
        $acpidump = (Get-Command "acpidump.exe" -ErrorAction SilentlyContinue).Source
    }
    
    if ($acpidump -and $elevated) {
        $hash = (Get-FileHash -Path $acpidump -Algorithm SHA256).Hash
        Write-Log "Using acpidump: $acpidump (SHA256: $hash)"
        Invoke-ExternalCommand -Command $acpidump -ArgsList @("-b") -OutFile (Join-Path $rawDir "acpi\acpidump-output.txt") | Out-Null
        # acpidump dumps to current working directory. We should move them.
        Move-Item -Path "*.dat" -Destination (Join-Path $rawDir "acpi\tables\") -ErrorAction SilentlyContinue
        return "PASS"
    } else {
        $reason = "acpidump.exe unavailable or not elevated"
        Set-Content -Path (Join-Path $rawDir "acpi\ACPIDUMP-NOT-CAPTURED.txt") -Value "tool missing or no elevation`ncapture remains outstanding"
        return "SKIPPED"
    }
}

# 9. EDID Capture
Run-Section "EDID Capture" {
    $edidIndex = @()
    $displays = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -Recurse -ErrorAction SilentlyContinue
    foreach ($d in $displays) {
        if ($d.Name -match "Device Parameters") {
            $val = Get-ItemProperty -Path $d.PSPath -Name "EDID" -ErrorAction SilentlyContinue
            if ($val -and $val.EDID) {
                $id = [guid]::NewGuid().ToString()
                $binPath = Join-Path $rawDir "display\edid\$id.bin"
                [System.IO.File]::WriteAllBytes($binPath, $val.EDID)
                $edidIndex += @{
                    RegistryPath = $d.Name
                    BinaryFilename = "$id.bin"
                    Length = $val.EDID.Length
                    SHA256 = (Get-FileHash -Path $binPath -Algorithm SHA256).Hash
                }
            }
        }
    }
    Export-SafeTsv -Data $edidIndex -Path (Join-Path $rawDir "display\edid-index.tsv")
    return "PASS"
}

# 10. Storage / NVMe
Run-Section "Storage" {
    $disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
    Export-SafeTsv -Data $disks -Path (Join-Path $publicDir "storage\disk-drives.tsv")
    return "PASS"
}

# 11. Secure Boot & BitLocker
Run-Section "Security" {
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        Export-SafeJson -Data @{ SecureBoot = $sb } -Path (Join-Path $publicDir "system\secureboot.json")
    } catch {
        Export-SafeJson -Data @{ SecureBoot = "unsupported or permission denied" } -Path (Join-Path $publicDir "system\secureboot.json")
    }
    
    if ($elevated) {
        $bde = Invoke-ExternalCommand -Command "manage-bde.exe" -ArgsList @("-status") -OutFile (Join-Path $rawDir "command-output\manage-bde-status.txt")
    }
    return "PASS"
}

# 12. Power Baseline
Run-Section "Power Baseline" {
    Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/a") -OutFile (Join-Path $rawDir "power\powercfg-a.txt") | Out-Null
    Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/requests") -OutFile (Join-Path $rawDir "power\powercfg-requests.txt") | Out-Null
    if ($elevated) {
        Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/batteryreport", "/output", (Join-Path $publicDir "power\batteryreport.html")) | Out-Null
        Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/sleepstudy", "/output", (Join-Path $publicDir "power\sleepstudy.html")) | Out-Null
        Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/qh") -OutFile (Join-Path $rawDir "power\powercfg-qh.txt") | Out-Null
    }
    return "PASS"
}

# 13. Reagent / BCD
Run-Section "Boot and Recovery" {
    if ($elevated) {
        Invoke-ExternalCommand -Command "reagentc.exe" -ArgsList @("/info") -OutFile (Join-Path $rawDir "uefi\reagentc-info.txt") | Out-Null
        Invoke-ExternalCommand -Command "bcdedit.exe" -ArgsList @("/enum", "all") -OutFile (Join-Path $rawDir "uefi\bcdedit-all.txt") | Out-Null
        Invoke-ExternalCommand -Command "bcdedit.exe" -ArgsList @("/enum", "firmware") -OutFile (Join-Path $rawDir "uefi\bcdedit-firmware.txt") | Out-Null
    } else {
        return "PARTIAL"
    }
    return "PASS"
}

# 14. Optional Export Drivers
Run-Section "Driver Export" {
    if ($ExportDrivers) {
        Write-Log "Exporting drivers. This will take time..."
        Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/export-driver", "*", (Join-Path $privateDir "drivers")) -OutFile (Join-Path $rawDir "command-output\pnputil-export-drivers.txt") | Out-Null
        return "PASS"
    }
    return "SKIPPED"
}

# Hashes
Write-Log "Calculating SHA256 Manifest..."
$hashManifestPath = Join-Path $OutputPath "SHA256SUMS.tsv"
$filesToHash = Get-ChildItem -Path $OutputPath -Recurse -File | Where-Object { $_.FullName -ne $hashManifestPath }
$hashes = @()
foreach ($f in $filesToHash) {
    $relPath = $f.FullName.Substring($OutputPath.Length+1)
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    $hashes += @{ RelativePath = $relPath; Size = $f.Length; SHA256 = $hash }
}
Export-SafeTsv -Data $hashes -Path $hashManifestPath

# Capture JSON
$CaptureEnd = (Get-Date).ToUniversalTime()
$HostHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($env:COMPUTERNAME))) -Algorithm SHA256).Hash

$CaptureMeta = @{
    schema_version = $SchemaVersion
    script_version = $ScriptVersion
    capture_start = $CaptureStart.ToString("yyyy-MM-ddTHH:mm:ssZ")
    capture_end = $CaptureEnd.ToString("yyyy-MM-ddTHH:mm:ssZ")
    timezone = [System.TimeZoneInfo]::Local.Id
    powershell_version = $PSVersionTable.PSVersion.ToString()
    windows_architecture = [System.Environment]::Is64BitOperatingSystem
    elevated = $elevated
    output_path = $OutputPath
    enabled_switches = @{ ExportDrivers = $ExportDrivers; CopyFirmware = $CopyFirmware }
    hostname_hash = $HostHash
    section_statuses = $SectionStatuses
}
Export-SafeJson -Data $CaptureMeta -Path (Join-Path $OutputPath "capture.json")

# Completion marker
Set-Content -Path (Join-Path $OutputPath "CAPTURE-COMPLETE.txt") -Value "Capture Complete`n$($CaptureEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))`nScript Version $ScriptVersion`nManifest: SHA256SUMS.tsv"

Write-Log "Day-0 Capture completed successfully."
if (-not $elevated) {
    Write-Log "REMINDER: An elevated second run is recommended to collect complete ACPI, registry, and power metadata."
}

