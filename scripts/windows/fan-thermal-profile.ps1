<#
.SYNOPSIS
Windows fan/thermal profile matching the Linux EC fan test.

.DESCRIPTION
Samples every 5 s: HP BIOS numeric sensors (this BIOS exposes none, and
Windows has no fan-speed interface), ACPI thermal zones (WMI and
performance counters; TZ31-TZ34 are the EC thermistors Linux also reads),
per-zone passive limits and throttle reasons, CPU utility, performance and
frequency, the energy meter rails, the power meter and AC state. The
protocol is 60 s idle, 60 s with every logical
CPU busy, then 120 s idle. It is the same as the Linux run in
docs/boot-log-battery-fan-review-2026-09-26.md (2482 -> 4028 -> 2776 RPM).

Read-only apart from the temporary CPU load. Run from an elevated Windows
PowerShell 5.1 with nothing else busy (no WSL builds). Output:
.work\windows-fan-profile-<timestamp>.tsv

.PARAMETER OutputDir
Directory for the TSV (default: the repository's .work).
#>
[CmdletBinding()]
param(
    [string]$OutputDir = '',
    [int]$IdleSeconds = 60,
    [int]$LoadSeconds = 60,
    [int]$RecoverySeconds = 120,
    [int]$IntervalSeconds = 5
)
$ErrorActionPreference = 'Stop'
# PowerShell 5.1 leaves $PSScriptRoot empty while parameter defaults are
# evaluated, so the default output directory is resolved here.
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.work'
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run this from an elevated Windows PowerShell (HP sensors and ACPI thermal WMI need it).'
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$out = Join-Path $OutputDir ("windows-fan-profile-{0}.tsv" -f (Get-Date -Format 'yyyyMMddTHHmmss'))

function Get-Sample([string]$phase, [double]$elapsed) {
    $rows = New-Object System.Collections.ArrayList
    $stamp = (Get-Date).ToString('o')
    try {
        foreach ($s in Get-CimInstance -Namespace root/HP/InstrumentedBIOS -ClassName HPBIOS_BIOSNumericSensor) {
            [void]$rows.Add("$stamp`t$phase`t$elapsed`thp_sensor`t$($s.Name)`t$($s.CurrentReading)`t$($s.BaseUnits)")
        }
    } catch { [void]$rows.Add("$stamp`t$phase`t$elapsed`terror`thp_sensor`t$($_.Exception.Message)`t") }
    try {
        foreach ($z in Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature) {
            $c = [math]::Round($z.CurrentTemperature / 10 - 273.15, 1)
            [void]$rows.Add("$stamp`t$phase`t$elapsed`tacpi_tz_wmi`t$($z.InstanceName)`t$c`tC")
        }
    } catch { [void]$rows.Add("$stamp`t$phase`t$elapsed`terror`tacpi_tz_wmi`t$($_.Exception.Message)`t") }
    try {
        foreach ($f in Get-CimInstance -ClassName Win32_Fan) {
            [void]$rows.Add("$stamp`t$phase`t$elapsed`twin32_fan`t$($f.DeviceID)`t$($f.DesiredSpeed)`tRPM")
        }
    } catch { [void]$rows.Add("$stamp`t$phase`t$elapsed`terror`twin32_fan`t$($_.Exception.Message)`t") }
    # One Get-Counter call: each call blocks for a one-second sample.
    # Linux under ACPI has no cpufreq (the firmware has no _CPC/_PSS), so the
    # Windows processor performance and frequency are part of the comparison.
    $cpu = -1
    try {
        $samples = (Get-Counter -Counter $counterPaths).CounterSamples
        foreach ($c in $samples) {
            $path = $c.Path.ToLowerInvariant()
            if ($path -like '*\thermal zone information(*)\temperature') {
                if ($c.CookedValue -gt 0) {
                    [void]$rows.Add("$stamp`t$phase`t$elapsed`tacpi_tz_counter`t$($c.InstanceName)`t$([math]::Round($c.CookedValue - 273.15, 1))`tC")
                }
            } elseif ($path -like '*\% processor utility') {
                $cpu = $c.CookedValue
            } elseif ($path -like '*\% processor performance') {
                [void]$rows.Add("$stamp`t$phase`t$elapsed`tcpufreq`tperformance`t$([math]::Round($c.CookedValue, 1))`t%")
            } elseif ($path -like '*\processor frequency') {
                [void]$rows.Add("$stamp`t$phase`t$elapsed`tcpufreq`tnominal_frequency`t$($c.CookedValue)`tMHz")
            } elseif ($path -like '*\% passive limit') {
                # Below 100 means that zone is throttling the CPUs.
                if ($c.CookedValue -lt 100) {
                    [void]$rows.Add("$stamp`t$phase`t$elapsed`ttz_passive_limit`t$($c.InstanceName)`t$($c.CookedValue)`t%")
                }
            } elseif ($path -like '*\throttle reasons') {
                if ($c.CookedValue -ne 0) {
                    [void]$rows.Add("$stamp`t$phase`t$elapsed`ttz_throttle_reasons`t$($c.InstanceName)`t$($c.CookedValue)`t")
                }
            } elseif ($path -like '*\energy meter(*)\power') {
                if ($c.InstanceName -ne '_total') {
                    [void]$rows.Add("$stamp`t$phase`t$elapsed`tenergy_meter`t$($c.InstanceName)`t$([math]::Round($c.CookedValue))`tmW")
                }
            } elseif ($path -like '*\power meter(*)\power') {
                if ($c.InstanceName -ne '_total') {
                    [void]$rows.Add("$stamp`t$phase`t$elapsed`tpower_meter`t$($c.InstanceName)`t$($c.CookedValue)`tmW")
                }
            }
        }
    } catch { [void]$rows.Add("$stamp`t$phase`t$elapsed`terror`tcounters`t$($_.Exception.Message)`t") }
    [void]$rows.Add("$stamp`t$phase`t$elapsed`tcpu`tutility`t$([math]::Round($cpu, 1))`t%")
    $ac = (Get-CimInstance -ClassName BatteryStatus -Namespace root/wmi -ErrorAction SilentlyContinue | Select-Object -First 1).PowerOnline
    [void]$rows.Add("$stamp`t$phase`t$elapsed`tpower`tac_online`t$ac`t")
    [IO.File]::AppendAllLines($out, [string[]]$rows)
    $fan = ($rows | Where-Object { $_ -match "`thp_sensor`t[^`t]*fan" }) -join ' | '
    Write-Host ("{0,-9} t={1,4}s cpu={2,5:N1}% {3}" -f $phase, $elapsed, $cpu, $fan)
}

$counterPaths = @(
    '\Thermal Zone Information(*)\Temperature',
    '\Processor Information(_Total)\% Processor Utility',
    '\Processor Information(_Total)\% Processor Performance',
    '\Processor Information(_Total)\Processor Frequency',
    '\Thermal Zone Information(*)\% Passive Limit',
    '\Thermal Zone Information(*)\Throttle Reasons',
    '\Energy Meter(*)\Power',
    '\Power Meter(*)\Power'
)
[IO.File]::WriteAllLines($out, [string[]]@("time`tphase`telapsed_s`tsource`tname`tvalue`tunit"))
$clock = [Diagnostics.Stopwatch]::StartNew()
$phases = @(@('idle', $IdleSeconds), @('load', $LoadSeconds), @('recovery', $RecoverySeconds))
$load = @()
try {
    foreach ($p in $phases) {
        if ($p[0] -eq 'load') {
            $n = [Environment]::ProcessorCount
            $load = 1..$n | ForEach-Object {
                Start-Process -PassThru -WindowStyle Hidden powershell.exe -ArgumentList '-NoProfile', '-Command', 'while ($true) { }'
            }
        }
        $end = $clock.Elapsed.TotalSeconds + $p[1]
        while ($clock.Elapsed.TotalSeconds -lt $end) {
            $tick = $clock.Elapsed.TotalSeconds
            Get-Sample $p[0] ([math]::Round($tick))
            # Keep the interval fixed: sampling itself takes a few seconds.
            $rest = $IntervalSeconds - ($clock.Elapsed.TotalSeconds - $tick)
            if ($rest -gt 0) { Start-Sleep -Milliseconds ([int]($rest * 1000)) }
        }
        if ($p[0] -eq 'load') { $load | Stop-Process -Force -ErrorAction SilentlyContinue; $load = @() }
    }
} finally {
    $load | Stop-Process -Force -ErrorAction SilentlyContinue
}
Write-Host "Saved $out"
