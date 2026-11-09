#Requires -Version 5.1
<#
Read-only evidence for where the Qualcomm firmware TPM (qcom.tz.tpm, "xCG
fTPM") keeps its persistent state, issue #19 (docs/tpm-2026-11-09.md).
Run once from an elevated Windows PowerShell:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\windows\tpm-storage-evidence.ps1

It writes nothing to the TPM, BitLocker or the registry. It lists file
names, sizes and times (never contents) in the TrEE file listener's folder
and the secure processor's data folder, before and after one read-only TPM
query (the endorsement key's public part, which the TPM reads from its
non-volatile storage), traces the TrEE driver during that query, and shows
BitLocker's TPM PCR profile (the TPM protector only; no recovery password).
The output folder is private: copy it into .work/, never commit it.
#>
$ErrorActionPreference = 'Continue'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run from an elevated PowerShell.'; exit 1
}
$out = Join-Path $env:USERPROFILE ("tpm-evidence-" + (Get-Date -Format 'yyyyMMddTHHmmss'))
New-Item -ItemType Directory -Force $out | Out-Null
$dirs = @('C:\Windows\System32\drivers\DriverData', 'C:\Windows\ServiceState\qcsp_8480\Data',
          'C:\Windows\ServiceState\qcsp_8480', 'C:\data')

function Get-Listing([string]$tag) {
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { "$d : absent"; continue }
        Get-ChildItem -LiteralPath $d -Force -Recurse -ErrorAction SilentlyContinue |
            Select-Object FullName, Length, CreationTime, LastWriteTime, LastAccessTime, Attributes |
            Sort-Object FullName | Format-Table -AutoSize | Out-String -Width 300
    }
}

"== system" | Out-File "$out\report.txt"
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion, ReleaseDate | Format-List | Out-File "$out\report.txt" -Append
tpmtool getdeviceinformation | Out-File "$out\report.txt" -Append

"== BitLocker TPM protector (PCR profile)" | Out-File "$out\report.txt" -Append
manage-bde -protectors -get C: -Type TPM | Out-File "$out\report.txt" -Append
manage-bde -status C: | Select-String -Pattern 'Conversion|Encryption Method|Protection Status|Key Protectors' |
    Out-File "$out\report.txt" -Append

"== TrEE autologger and its trace files" | Out-File "$out\report.txt" -Append
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\TrEE' -ErrorAction SilentlyContinue |
    Format-List | Out-File "$out\report.txt" -Append
Get-ChildItem 'C:\Windows\System32\LogFiles\WMI' -Filter '*TrEE*' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-File "$out\report.txt" -Append

"== TrEE secure services (registry)" | Out-File "$out\report.txt" -Append
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\QcTrEE_8480\Parameters' -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name; (Get-ItemProperty $_.PSPath | Format-List | Out-String -Width 200) } |
    Out-File "$out\report.txt" -Append

Get-Listing 'before' | Out-File "$out\listing-before.txt"

# Trace the TrEE driver (WPP provider of its autologger) during one read-only query.
$session = 'GlymurTrEE'
logman stop $session -ets 2>$null | Out-Null
logman create trace $session -ets -p '{DE3B1201-A1DF-478A-9062-E443CDABF070}' 0xFFFFFFFF 0xFF -o "$out\tree-trace.etl" |
    Out-File "$out\report.txt" -Append
Start-Sleep -Seconds 2
"== endorsement key query (read-only), $(Get-Date -Format o)" | Out-File "$out\report.txt" -Append
try { Get-TpmEndorsementKeyInfo -HashAlgorithm Sha256 | Select-Object IsPresent, PublicKeyHash |
        Format-List | Out-File "$out\report.txt" -Append }
catch { "query failed: $($_.Exception.Message)" | Out-File "$out\report.txt" -Append }
Start-Sleep -Seconds 5
logman stop $session -ets | Out-File "$out\report.txt" -Append

Get-Listing 'after' | Out-File "$out\listing-after.txt"
"== changes between the listings" | Out-File "$out\report.txt" -Append
Compare-Object (Get-Content "$out\listing-before.txt") (Get-Content "$out\listing-after.txt") |
    Out-String -Width 300 | Out-File "$out\report.txt" -Append

Write-Host "Done. Copy $out into the repository's .work\ (private)."
