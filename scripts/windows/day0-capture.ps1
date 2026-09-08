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

.PARAMETER Preflight
Optional. If specified, performs safety and environment checks and exits without capturing.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [switch]$ExportDrivers,
    [switch]$CopyFirmware,
    [switch]$Preflight,

    [string]$AcpiToolsPath
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.1"
$SchemaVersion = 1

# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Warning "This script requires Windows PowerShell 5.1 or newer. Your version is $($PSVersionTable.PSVersion.ToString())."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "helpers.ps1")

$elevated = Test-Elevated

if ($Preflight) {
    Write-Host "--- DAY-0 CAPTURE PREFLIGHT ---"
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion.ToString())"
    Write-Host "Architecture: $(if ([Environment]::Is64BitOperatingSystem) {'64-bit'} else {'32-bit'})"
    Write-Host "Elevated: $elevated"
    
    $pnpAvail = Get-Command "Get-PnpDevice" -ErrorAction SilentlyContinue
    Write-Host "Get-PnpDevice available: $(if ($pnpAvail) {'True'} else {'False'})"
    
    if (-not $pnpAvail) {
        Write-Host "STATUS: READY WITH WARNINGS (Missing PnpDevice module, will fallback)"
    } elseif (-not $elevated) {
        Write-Host "STATUS: READY WITH WARNINGS (Not elevated, ACPI/Power will be partial)"
    } else {
        Write-Host "STATUS: READY"
    }
    
    # Estimate space
    $drive = Split-Path $OutputPath -Qualifier
    if ($drive) {
        $vol = Get-Volume -DriveLetter $drive[0] -ErrorAction SilentlyContinue
        if ($vol) {
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
            Write-Host "Free space on $drive : ${freeGB} GB"
            if ($ExportDrivers -and $freeGB -lt 5) {
                Write-Host "WARNING: -ExportDrivers may require significant space."
            }
        }
    }
    exit 0
}

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
        SystemSKUNumber = if ($csProduct) {$csProduct.SKUNumber} else {$null}
        SMBIOSUUID = if ($csProduct) {$csProduct.UUID} else {$null}
        BaseBoardSerial = if ($baseBoard) {$baseBoard.SerialNumber} else {$null}
        BIOSSerial = if ($bios) {$bios.SerialNumber} else {$null}
        ComputerName = if ($cs) {$cs.Name} else {$null}
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
        Manufacturer = if ($cs) {$cs.Manufacturer} else {$null}
        Model = if ($cs) {$cs.Model} else {$null}
        SystemFamily = if ($cs) {$cs.SystemFamily} else {$null}
        BaseBoardProduct = if ($baseBoard) {$baseBoard.Product} else {$null}
        BaseBoardVersion = if ($baseBoard) {$baseBoard.Version} else {$null}
        BIOSVersion = if ($bios) {$bios.SMBIOSBIOSVersion} else {$null}
        BIOSDate = if ($bios) {$bios.ReleaseDate} else {$null}
        OSBuild = if ($os) {$os.BuildNumber} else {$null}
        OSArchitecture = if ($os) {$os.OSArchitecture} else {$null}
        OSEdition = if ($os) {$os.Caption} else {$null}
    }
    Export-SafeJson -Data $sysData -Path (Join-Path $publicDir "system\system-info.json")
    
    Invoke-ExternalCommand -Command "systeminfo.exe" -ArgsList @() -OutFile (Join-Path $rawDir "command-output\systeminfo.txt") | Out-Null
    Write-Log "Invoking msinfo32 /report (this may take a moment)..."
    Invoke-ExternalCommand -Command "msinfo32.exe" -ArgsList @("/report", (Join-Path $rawDir "command-output\msinfo32.txt")) | Out-Null

    return "PASS"
}

# 3. Complete PnP Inventory
Run-Section "PnP Inventory" {
    if (Get-Command "Get-PnpDevice" -ErrorAction SilentlyContinue) {
        $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
        Export-SafeTsv -Data $devices -Path (Join-Path $publicDir "pnp\devices.tsv")
        
        $allProps = @()
        foreach ($dev in $devices) {
            $props = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue
            foreach ($p in $props) {
                $allProps += @{
                    InstanceId = $dev.InstanceId
                    KeyName = $p.KeyName
                    Data = if ($p.Data -ne $null) {$p.Data.ToString()} else {$null}
                    Type = $p.Type
                }
            }
        }
        Export-SafeJson -Data $allProps -Path (Join-Path $rawDir "pnp\all-properties.json")
    } else {
        Write-Log "Get-PnpDevice unavailable." -Level "WARNING"
        return "PARTIAL"
    }
    return "PASS"
}

# 4. PnPUtil Enumeration
Run-Section "PnPUtil Enumeration" {
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
    if ($drivers) {
        Export-SafeTsv -Data $drivers -Path (Join-Path $publicDir "drivers\signed-drivers.tsv")
    }
    Invoke-ExternalCommand -Command "driverquery.exe" -ArgsList @("/v", "/fo", "csv") -OutFile (Join-Path $rawDir "command-output\driverquery.csv") | Out-Null
    Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/enum-drivers") -OutFile (Join-Path $rawDir "command-output\pnputil-enum-drivers.txt") | Out-Null
    return "PASS"
}

# 6. Factory DriverStore Inventory
Run-Section "Factory DriverStore" {
    $dsPath = Join-Path $env:windir "System32\DriverStore\FileRepository"
    if (Test-Path $dsPath) {
        $files = Get-ChildItem -Path $dsPath -Recurse -File -ErrorAction SilentlyContinue
        $inventory = @()
        foreach ($f in $files) {
            $inventory += @{
                Name = $f.Name
                RelativePath = $f.FullName.Substring($dsPath.Length+1)
                Extension = $f.Extension
                Length = $f.Length
                LastWriteTime = $f.LastWriteTime.ToString("o")
            }
        }
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
                # Ensure no path traversal
                $cleanRelPath = $c.RelativePath -replace '\.\.', ''
                $targetPath = Join-Path $privateDir "firmware\$($c.SourcePackage)\$($c.Filename)"
                $targetDir = Split-Path $targetPath -Parent
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
                Copy-Item -Path (Join-Path $dsPath $cleanRelPath) -Destination $targetPath -ErrorAction SilentlyContinue
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
        Move-Item -Path "*.dat" -Destination (Join-Path $rawDir "acpi\tables\") -ErrorAction SilentlyContinue
        return "PASS"
    } else {
        $reason = "acpidump.exe unavailable or not elevated"
        Set-Content -Path (Join-Path $rawDir "acpi\ACPIDUMP-NOT-CAPTURED.txt") -Value "tool missing or no elevation`ncapture remains outstanding" -Encoding UTF8
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
    if ($edidIndex.Count -gt 0) {
        Export-SafeTsv -Data $edidIndex -Path (Join-Path $rawDir "display\edid-index.tsv")
    }
    return "PASS"
}

# 10. Storage / NVMe
Run-Section "Storage" {
    $disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
    if ($disks) {
        Export-SafeTsv -Data $disks -Path (Join-Path $publicDir "storage\disk-drives.tsv")
    }
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
        Invoke-ExternalCommand -Command "manage-bde.exe" -ArgsList @("-status") -OutFile (Join-Path $rawDir "command-output\manage-bde-status.txt") | Out-Null
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
Set-Content -Path (Join-Path $OutputPath "CAPTURE-COMPLETE.txt") -Value "Capture Complete`n$($CaptureEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))`nScript Version $ScriptVersion`nManifest: SHA256SUMS.tsv" -Encoding UTF8

Write-Log "Day-0 Capture completed successfully."
if (-not $elevated) {
    Write-Log "REMINDER: An elevated second run is recommended to collect complete ACPI, registry, and power metadata."
}

