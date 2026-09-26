<#
.SYNOPSIS
Day-0 Hardware Capture Tool for HP OmniBook 5 16-bf1xxx

.DESCRIPTION
Captures metadata, ACPI, PnP, and Driver information read-only.
This script must NOT modify system state.
Compatible with Windows PowerShell 5.1.

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
$ScriptVersion = "0.2.1"
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
    Write-Host "Script Version: $ScriptVersion"
    Write-Host "Schema Version: $SchemaVersion"
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion.ToString())"

    $archStr = "32-bit"
    if ([Environment]::Is64BitOperatingSystem) { $archStr = "64-bit" }
    Write-Host "Architecture: $archStr"
    Write-Host "Elevated: $elevated"

    $pnpAvail = Get-Command "Get-PnpDevice" -ErrorAction SilentlyContinue
    $pnpStr = "False"
    if ($pnpAvail) { $pnpStr = "True" }
    Write-Host "Get-PnpDevice available: $pnpStr"

    # Check for candidate JSON
    $candidatesFile = Join-Path $ScriptDir "day0-candidates.json"
    if (Test-Path $candidatesFile) {
        Write-Host "Candidate JSON: Present"
    } else {
        Write-Host "Candidate JSON: MISSING"
    }

    # Check required commands
    $requiredCmds = @("systeminfo.exe", "pnputil.exe", "driverquery.exe", "powercfg.exe", "reg.exe")
    $missingCmds = @()
    foreach ($cmd in $requiredCmds) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missingCmds += $cmd
        }
    }
    if ($missingCmds.Count -gt 0) {
        Write-Host "MISSING REQUIRED COMMANDS: $($missingCmds -join ', ')"
        Write-Host "STATUS: BLOCKED"
        exit 1
    }
    Write-Host "Required commands: All present"

    # Check optional commands
    $optionalCmds = @("msinfo32.exe", "manage-bde.exe", "bcdedit.exe", "reagentc.exe")
    foreach ($cmd in $optionalCmds) {
        $avail = Get-Command $cmd -ErrorAction SilentlyContinue
        $availStr = "Available"
        if (-not $avail) { $availStr = "Not found" }
        Write-Host "Optional: $cmd = $availStr"
    }

    # ACPICA tools
    $acpidumpPath = ""
    $iaslPath = ""
    if ($AcpiToolsPath) {
        $candidateAcpiDump = Join-Path $AcpiToolsPath "acpidump.exe"
        $candidateIasl = Join-Path $AcpiToolsPath "iasl.exe"
        if (Test-Path $candidateAcpiDump) { $acpidumpPath = $candidateAcpiDump }
        if (Test-Path $candidateIasl) { $iaslPath = $candidateIasl }
    }
    if (-not $acpidumpPath) {
        $foundAcpiDump = Get-Command "acpidump.exe" -ErrorAction SilentlyContinue
        if ($foundAcpiDump) { $acpidumpPath = $foundAcpiDump.Source }
    }
    if (-not $iaslPath -and $acpidumpPath) {
        $siblingIasl = Join-Path (Split-Path -Parent $acpidumpPath) "iasl.exe"
        if (Test-Path $siblingIasl) { $iaslPath = $siblingIasl }
    }
    if (-not $iaslPath) {
        $foundIasl = Get-Command "iasl.exe" -ErrorAction SilentlyContinue
        if ($foundIasl) { $iaslPath = $foundIasl.Source }
    }
    if ($acpidumpPath -and $iaslPath) {
        $acpiStatus = "Available (acpidump.exe + iasl.exe)"
    } elseif ($acpidumpPath) {
        $acpiStatus = "Available (acpidump.exe only; iasl.exe not found)"
    } elseif ($AcpiToolsPath) {
        $acpiStatus = "Path specified but acpidump.exe not found"
    } else {
        $acpiStatus = "Not configured"
    }
    Write-Host "ACPICA tools: $acpiStatus"

    # Estimate space
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $drive = Split-Path $OutputPath -Qualifier -ErrorAction SilentlyContinue
    if ($drive -and $drive -match '^[A-Za-z]:$') {
        $vol = Get-Volume -DriveLetter $drive[0] -ErrorAction SilentlyContinue
        if ($vol) {
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
            Write-Host "Free space on ${drive}: ${freeGB} GB"
            if ($ExportDrivers -and $freeGB -lt 5) {
                Write-Host "WARNING: -ExportDrivers may require significant space."
            }
            if ($freeGB -lt 1) {
                Write-Host "WARNING: Less than 1 GB free. Capture may fail."
            }
        }
    }

    # Overall status
    if (-not $pnpAvail -and -not $elevated) {
        Write-Host "STATUS: READY WITH WARNINGS (Missing PnpDevice module AND not elevated)"
    } elseif (-not $pnpAvail) {
        Write-Host "STATUS: READY WITH WARNINGS (Missing PnpDevice module, will fallback)"
    } elseif (-not $elevated) {
        Write-Host "STATUS: READY WITH WARNINGS (Not elevated, ACPI/Power will be partial)"
    } else {
        Write-Host "STATUS: READY"
    }
    exit 0
}

# Validate OutputPath
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ($OutputPath.StartsWith($env:windir, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "OutputPath must not be inside the Windows directory."
    exit 1
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
    (Join-Path $privateDir "firmware"),
    (Join-Path $privateDir "security")
)

foreach ($d in $dirsToCreate) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

$global:CaptureLogPath = Join-Path $logsDir "capture.log"
$global:FailuresLogPath = Join-Path $logsDir "failures.log"

Write-Log "Starting Day-0 Capture (Version $ScriptVersion, Schema $SchemaVersion)"
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

function Get-SectionStatusFromResults {
    param([object[]]$Results)
    foreach ($result in $Results) {
        if ($null -eq $result -or $result.ExitCode -ne 0) {
            return "PARTIAL"
        }
    }
    return "PASS"
}

# 1. Private Identity
Run-Section "Private Identity" {
    $csProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $idData = @{
        SystemSKUNumber = (Get-SafeProperty $csProduct 'SKUNumber')
        SMBIOSUUID      = (Get-SafeProperty $csProduct 'UUID')
        BaseBoardSerial = (Get-SafeProperty $baseBoard 'SerialNumber')
        BIOSSerial      = (Get-SafeProperty $bios 'SerialNumber')
        ComputerName    = (Get-SafeProperty $cs 'Name')
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
        Manufacturer     = (Get-SafeProperty $cs 'Manufacturer')
        Model            = (Get-SafeProperty $cs 'Model')
        SystemFamily     = (Get-SafeProperty $cs 'SystemFamily')
        BaseBoardProduct = (Get-SafeProperty $baseBoard 'Product')
        BaseBoardVersion = (Get-SafeProperty $baseBoard 'Version')
        BIOSVersion      = (Get-SafeProperty $bios 'SMBIOSBIOSVersion')
        BIOSDate         = (Get-SafeProperty $bios 'ReleaseDate')
        OSBuild          = (Get-SafeProperty $os 'BuildNumber')
        OSArchitecture   = (Get-SafeProperty $os 'OSArchitecture')
        OSEdition        = (Get-SafeProperty $os 'Caption')
    }
    Export-SafeJson -Data $sysData -Path (Join-Path $publicDir "system\system-info.json")

    $systemInfoResult = Invoke-ExternalCommand -Command "systeminfo.exe" -ArgsList @() -OutFile (Join-Path $rawDir "command-output\systeminfo.txt")
    Write-Log "Invoking msinfo32 /report (this may take a moment)..."
    $msInfoResult = Invoke-ExternalCommand -Command "msinfo32.exe" -ArgsList @("/report", (Join-Path $rawDir "command-output\msinfo32.txt"))

    return (Get-SectionStatusFromResults @($systemInfoResult, $msInfoResult))
}

# 3. Complete PnP Inventory
Run-Section "PnP Inventory" {
    if (Get-Command "Get-PnpDevice" -ErrorAction SilentlyContinue) {
        $devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
        Export-SafeTsv -Data $devices -Path (Join-Path $publicDir "pnp\devices.tsv")

        $allProps = [System.Collections.ArrayList]::new()
        foreach ($dev in $devices) {
            $props = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue
            foreach ($p in $props) {
                $dataStr = $null
                if ($null -ne $p.Data) { $dataStr = $p.Data.ToString() }
                [void]$allProps.Add([PSCustomObject]@{
                    InstanceId = $dev.InstanceId
                    KeyName    = $p.KeyName
                    Data       = $dataStr
                    Type       = $p.Type
                })
            }
        }
        Export-SafeJson -Data @($allProps) -Path (Join-Path $rawDir "pnp\all-properties.json")
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
        $fallback = Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/enum-devices", "/connected") -OutFile (Join-Path $rawDir "command-output\pnputil-enum-devices-basic.txt")
        return (Get-SectionStatusFromResults @($res, $fallback))
    }
    return "PASS"
}

# 5. Driver Inventory
Run-Section "Driver Inventory" {
    $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue
    if ($drivers) {
        Export-SafeTsv -Data $drivers -Path (Join-Path $publicDir "drivers\signed-drivers.tsv")
    }
    $driverQueryResult = Invoke-ExternalCommand -Command "driverquery.exe" -ArgsList @("/v", "/fo", "csv") -OutFile (Join-Path $rawDir "command-output\driverquery.csv")
    $pnputilResult = Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/enum-drivers") -OutFile (Join-Path $rawDir "command-output\pnputil-enum-drivers.txt")
    return (Get-SectionStatusFromResults @($driverQueryResult, $pnputilResult))
}

# 6. Factory DriverStore Inventory
Run-Section "Factory DriverStore" {
    $dsPath = Join-Path $env:windir "System32\DriverStore\FileRepository"
    if (Test-Path $dsPath) {
        $files = Get-ChildItem -Path $dsPath -Recurse -File -ErrorAction SilentlyContinue
        $inventory = [System.Collections.ArrayList]::new()
        foreach ($f in $files) {
            [void]$inventory.Add([PSCustomObject]@{
                Name          = $f.Name
                RelativePath  = $f.FullName.Substring($dsPath.Length+1)
                Extension     = $f.Extension
                Length        = $f.Length
                LastWriteTime = $f.LastWriteTime.ToString("o")
            })
        }
        Export-SafeTsv -Data @($inventory) -Path (Join-Path $rawDir "firmware\driverstore-file-inventory.tsv")

        $candidates = [System.Collections.ArrayList]::new()
        $fwExts = @('.mbn','.elf','.melf','.bin','.fw','.bdf','.tlv','.jsn','.json','.dat','.cfg')
        foreach ($f in $files) {
            if ($fwExts -contains $f.Extension.ToLower()) {
                [void]$candidates.Add([PSCustomObject]@{
                    Filename     = $f.Name
                    RelativePath = $f.FullName.Substring($dsPath.Length+1)
                    Size         = $f.Length
                    SHA256       = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
                    SourcePackage = $f.Directory.Name
                })
            }
        }
        Export-SafeTsv -Data @($candidates) -Path (Join-Path $rawDir "firmware\candidates.tsv")

        if ($CopyFirmware) {
            foreach ($c in $candidates) {
                # Validate path safety: resolve full path and ensure it stays under dsPath
                $sourceFull = [System.IO.Path]::GetFullPath((Join-Path $dsPath $c.RelativePath))
                if (-not $sourceFull.StartsWith($dsPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-Log "Path traversal detected, skipping: $($c.RelativePath)" -Level "WARNING"
                    continue
                }
                $targetPath = Join-Path $privateDir "firmware\$($c.SourcePackage)\$($c.Filename)"
                $targetDir = Split-Path $targetPath -Parent
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
                Copy-Item -Path $sourceFull -Destination $targetPath -ErrorAction SilentlyContinue
            }
        }
    } else {
        return "PARTIAL"
    }
    return "PASS"
}

# 7. ACPI Registry
Run-Section "ACPI Registry" {
    if ($elevated) {
        $registryResults = @()
        $registryResults += Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\HARDWARE\ACPI", (Join-Path $rawDir "registry\HKLM_HARDWARE_ACPI.reg"), "/y")
        $registryResults += Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_ACPI.reg"), "/y")
        $registryResults += Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\PCI", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_PCI.reg"), "/y")
        $registryResults += Invoke-ExternalCommand -Command "reg.exe" -ArgsList @("export", "HKLM\SYSTEM\CurrentControlSet\Enum\USB", (Join-Path $rawDir "registry\HKLM_SYSTEM_CCS_Enum_USB.reg"), "/y")
        return (Get-SectionStatusFromResults $registryResults)
    } else {
        return "PARTIAL"
    }
}

# 8. ACPI Tools (Optional)
Run-Section "ACPI Tools" {
    $acpidump = ""
    $iasl = ""
    if ($AcpiToolsPath) {
        $candidate = Join-Path $AcpiToolsPath "acpidump.exe"
        if (Test-Path $candidate) { $acpidump = $candidate }
        $iaslCandidate = Join-Path $AcpiToolsPath "iasl.exe"
        if (Test-Path $iaslCandidate) { $iasl = $iaslCandidate }
    }
    if (-not $acpidump) {
        $found = Get-Command "acpidump.exe" -ErrorAction SilentlyContinue
        if ($found) { $acpidump = $found.Source }
    }
    if (-not $iasl -and $acpidump) {
        $siblingIasl = Join-Path (Split-Path -Parent $acpidump) "iasl.exe"
        if (Test-Path $siblingIasl) { $iasl = $siblingIasl }
    }
    if (-not $iasl) {
        $foundIasl = Get-Command "iasl.exe" -ErrorAction SilentlyContinue
        if ($foundIasl) { $iasl = $foundIasl.Source }
    }

    if ($acpidump -and $elevated) {
        $hash = (Get-FileHash -Path $acpidump -Algorithm SHA256).Hash
        Write-Log "Using acpidump: $acpidump (SHA256: $hash)"
        # Run acpidump from the target tables directory so .dat files land there
        $acpiTablesDir = Join-Path $rawDir "acpi\tables"
        Push-Location $acpiTablesDir
        try {
            $acpiResult = Invoke-ExternalCommand -Command $acpidump -ArgsList @("-b") -OutFile (Join-Path $rawDir "acpi\acpidump-output.txt")
        } finally {
            Pop-Location
        }
        if ($acpiResult.ExitCode -ne 0) { return "FAIL" }

        if ($iasl) {
            $iaslHash = (Get-FileHash -Path $iasl -Algorithm SHA256).Hash
            Write-Log "Using iasl: $iasl (SHA256: $iaslHash)"
            $dsdtPath = Join-Path $acpiTablesDir "dsdt.dat"
            $externalTables = @(Get-ChildItem -Path $acpiTablesDir -Filter "ssdt*.dat" -File | Sort-Object Name)
            $aslDir = Join-Path $rawDir "acpi\asl"
            New-Item -ItemType Directory -Path $aslDir -Force | Out-Null
            if ((Test-Path $dsdtPath) -and $externalTables.Count -gt 0) {
                # Keep -p before input files. ACPICA treats an option appearing
                # after the DSDT path as another input file.
                $iaslArgs = @("-p", (Join-Path $aslDir "glymur"), "-e") + @($externalTables | ForEach-Object { $_.FullName }) + @("-d", $dsdtPath)
                $iaslResult = Invoke-ExternalCommand -Command $iasl -ArgsList $iaslArgs -OutFile (Join-Path $rawDir "acpi\iasl-decompile-output.txt") -ErrFile (Join-Path $rawDir "acpi\iasl-decompile-errors.txt")
                if ($iaslResult.ExitCode -ne 0) {
                    Write-Log "iasl combined decompilation failed; binary tables were captured." -Level "WARNING"
                    return "PARTIAL"
                }
            } else {
                Write-Log "iasl found, but dsdt.dat or ssdt*.dat inputs are missing." -Level "WARNING"
                return "PARTIAL"
            }
        } else {
            $noteContent = "iasl.exe unavailable; binary ACPI tables were captured but combined ASL decompilation was not run."
            [System.IO.File]::WriteAllText((Join-Path $rawDir "acpi\IASL-NOT-RUN.txt"), $noteContent, $global:Utf8NoBom)
        }
        return "PASS"
    } else {
        $reason = "acpidump.exe unavailable or not elevated"
        $noteContent = "tool missing or no elevation`ncapture remains outstanding"
        [System.IO.File]::WriteAllText((Join-Path $rawDir "acpi\ACPIDUMP-NOT-CAPTURED.txt"), $noteContent, $global:Utf8NoBom)
        return "SKIPPED"
    }
}

# 9. EDID Capture
Run-Section "EDID Capture" {
    $edidIndex = [System.Collections.ArrayList]::new()
    $displays = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -Recurse -ErrorAction SilentlyContinue
    foreach ($d in $displays) {
        if ($d.Name -match "Device Parameters") {
            $val = Get-ItemProperty -Path $d.PSPath -Name "EDID" -ErrorAction SilentlyContinue
            if ($val -and $val.EDID) {
                $id = [guid]::NewGuid().ToString()
                $binPath = Join-Path $rawDir "display\edid\$id.bin"
                [System.IO.File]::WriteAllBytes($binPath, $val.EDID)
                [void]$edidIndex.Add([PSCustomObject]@{
                    RegistryPath   = $d.Name
                    BinaryFilename = "$id.bin"
                    Length         = $val.EDID.Length
                    SHA256         = (Get-FileHash -Path $binPath -Algorithm SHA256).Hash
                })
            }
        }
    }
    if ($edidIndex.Count -gt 0) {
        Export-SafeTsv -Data @($edidIndex) -Path (Join-Path $rawDir "display\edid-index.tsv")
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
    $status = "PASS"
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        Export-SafeJson -Data @{ SecureBoot = $sb } -Path (Join-Path $publicDir "system\secureboot.json")
    } catch {
        Export-SafeJson -Data @{ SecureBoot = "unsupported or permission denied" } -Path (Join-Path $publicDir "system\secureboot.json")
    }

    # BitLocker status goes to private/ since it may contain key protector IDs
    if ($elevated) {
        $bitlockerResult = Invoke-ExternalCommand -Command "manage-bde.exe" -ArgsList @("-status") -OutFile (Join-Path $privateDir "security\manage-bde-status.txt")
        if ($bitlockerResult.ExitCode -ne 0) { $status = "PARTIAL" }
    } else {
        $status = "PARTIAL"
    }
    return $status
}

# 12. Power Baseline
Run-Section "Power Baseline" {
    $powerResults = @()
    $powerResults += Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/a") -OutFile (Join-Path $rawDir "power\powercfg-a.txt")
    $powerResults += Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/requests") -OutFile (Join-Path $rawDir "power\powercfg-requests.txt")
    if ($elevated) {
        $powerResults += Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/batteryreport", "/output", (Join-Path $publicDir "power\batteryreport.html"))
        $powerResults += Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/sleepstudy", "/output", (Join-Path $publicDir "power\sleepstudy.html"))
        $powerResults += Invoke-ExternalCommand -Command "powercfg.exe" -ArgsList @("/qh") -OutFile (Join-Path $rawDir "power\powercfg-qh.txt")
    }
    return (Get-SectionStatusFromResults $powerResults)
}

# 13. Reagent / BCD
Run-Section "Boot and Recovery" {
    if ($elevated) {
        $bootResults = @()
        $bootResults += Invoke-ExternalCommand -Command "reagentc.exe" -ArgsList @("/info") -OutFile (Join-Path $rawDir "uefi\reagentc-info.txt")
        $bootResults += Invoke-ExternalCommand -Command "bcdedit.exe" -ArgsList @("/enum", "all") -OutFile (Join-Path $rawDir "uefi\bcdedit-all.txt")
        $bootResults += Invoke-ExternalCommand -Command "bcdedit.exe" -ArgsList @("/enum", "firmware") -OutFile (Join-Path $rawDir "uefi\bcdedit-firmware.txt")
        return (Get-SectionStatusFromResults $bootResults)
    } else {
        return "PARTIAL"
    }
    return "PASS"
}

# 14. Optional Export Drivers
Run-Section "Driver Export" {
    if ($ExportDrivers) {
        Write-Log "Exporting drivers. This will take time..."
        $exportResult = Invoke-ExternalCommand -Command "pnputil.exe" -ArgsList @("/export-driver", "*", (Join-Path $privateDir "drivers")) -OutFile (Join-Path $rawDir "command-output\pnputil-export-drivers.txt")
        if ($exportResult.ExitCode -eq 0) { return "PASS" }
        return "FAIL"
    }
    return "SKIPPED"
}

# All logging complete before hash generation
Write-Log "All capture sections complete. Calculating SHA256 Manifest..."

# Capture metadata and the completion marker are written before hashing so the
# manifest covers every non-log output file, not just the section outputs.
$CaptureEnd = (Get-Date).ToUniversalTime()
$HostHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($env:COMPUTERNAME))) -Algorithm SHA256).Hash

$CaptureMeta = @{
    schema_version       = $SchemaVersion
    script_version       = $ScriptVersion
    capture_start        = $CaptureStart.ToString("yyyy-MM-ddTHH:mm:ssZ")
    capture_end          = $CaptureEnd.ToString("yyyy-MM-ddTHH:mm:ssZ")
    timezone             = [System.TimeZoneInfo]::Local.Id
    powershell_version   = $PSVersionTable.PSVersion.ToString()
    windows_architecture = [System.Environment]::Is64BitOperatingSystem
    elevated             = $elevated
    output_path          = $OutputPath
    enabled_switches     = @{ ExportDrivers = [bool]$ExportDrivers; CopyFirmware = [bool]$CopyFirmware }
    hostname_hash        = $HostHash
    section_statuses     = $SectionStatuses
}
Export-SafeJson -Data $CaptureMeta -Path (Join-Path $OutputPath "capture.json")

$completionText = "Capture Complete`n$($CaptureEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))`nScript Version $ScriptVersion`nManifest: SHA256SUMS.tsv"
[System.IO.File]::WriteAllText((Join-Path $OutputPath "CAPTURE-COMPLETE.txt"), $completionText, $global:Utf8NoBom)

# Hashes — exclude log files and the manifest itself since logs are still being written
$hashManifestPath = Join-Path $OutputPath "SHA256SUMS.tsv"
$logsFullPath = [System.IO.Path]::GetFullPath($logsDir)
$filesToHash = Get-ChildItem -Path $OutputPath -Recurse -File | Where-Object {
    $_.FullName -ne $hashManifestPath -and
    -not $_.FullName.StartsWith($logsFullPath, [System.StringComparison]::OrdinalIgnoreCase)
}
$hashes = [System.Collections.ArrayList]::new()
foreach ($f in $filesToHash) {
    $relPath = $f.FullName.Substring($OutputPath.Length+1)
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    [void]$hashes.Add([PSCustomObject]@{ RelativePath = $relPath; Size = $f.Length; SHA256 = $hash })
}
Export-SafeTsv -Data @($hashes) -Path $hashManifestPath

Write-Log "Day-0 Capture completed successfully."
if (-not $elevated) {
    Write-Log "REMINDER: An elevated second run is recommended to collect complete ACPI, registry, and power metadata."
}
