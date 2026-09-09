# Helper functions for Day-0 Capture
# Compatible with Windows PowerShell 5.1

$global:CaptureLogPath = ""
$global:FailuresLogPath = ""

# UTF-8 encoding without BOM for cross-platform compatibility
$global:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-SafeProperty {
    param($Obj, [string]$Prop)
    if ($null -ne $Obj) { $Obj.$Prop } else { $null }
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine
    if ($global:CaptureLogPath) {
        [System.IO.File]::AppendAllText($global:CaptureLogPath, "$logLine`r`n", $global:Utf8NoBom)
    }
    if ($Level -eq "ERROR" -or $Level -eq "WARNING") {
        if ($global:FailuresLogPath) {
            [System.IO.File]::AppendAllText($global:FailuresLogPath, "$logLine`r`n", $global:Utf8NoBom)
        }
    }
}

function Test-Elevated {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ExternalCommand {
    param(
        [string]$Command,
        [string[]]$ArgsList,
        [string]$OutFile,
        [string]$ErrFile,
        [int]$TimeoutSeconds = 0
    )
    Write-Log "Executing: $Command $($ArgsList -join ' ')"
    $startTime = (Get-Date).ToUniversalTime()

    # We use Start-Process with Wait and RedirectStandardOutput to safely execute without Invoke-Expression
    try {
        $procArgs = @{
            FilePath = $Command
            ArgumentList = $ArgsList
            Wait = $true
            NoNewWindow = $true
            PassThru = $true
        }
        if ($OutFile) { $procArgs.RedirectStandardOutput = $OutFile }
        if ($ErrFile) { $procArgs.RedirectStandardError = $ErrFile }

        $proc = Start-Process @procArgs
        $exitCode = $proc.ExitCode
        $endTime = (Get-Date).ToUniversalTime()
        Write-Log "Command finished with exit code $exitCode"
        return @{ ExitCode = $exitCode; StartTime = $startTime; EndTime = $endTime }
    } catch {
        Write-Log "Command failed to execute: $_" -Level "ERROR"
        return @{ ExitCode = -1; StartTime = $startTime; EndTime = (Get-Date).ToUniversalTime(); Error = $_.Exception.Message }
    }
}

function Export-SafeJson {
    param (
        [Parameter(Mandatory=$true)] $Data,
        [Parameter(Mandatory=$true)] [string]$Path,
        [int]$Depth = 100
    )
    try {
        $parentDir = Split-Path $Path -Parent
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        # Use -InputObject to preserve array wrapper; pipe serializes elements individually
        $json = ConvertTo-Json -InputObject $Data -Depth $Depth
        [System.IO.File]::WriteAllText($Path, $json, $global:Utf8NoBom)
    } catch {
        Write-Log "Failed to export JSON to $Path : $_" -Level "ERROR"
    }
}

function Export-SafeTsv {
    param (
        [Parameter(Mandatory=$true)] $Data,
        [Parameter(Mandatory=$true)] [string]$Path
    )
    try {
        $parentDir = Split-Path $Path -Parent
        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        # Convert hashtables to PSCustomObject for Export-Csv compatibility
        $converted = foreach ($item in $Data) {
            if ($item -is [hashtable]) {
                [PSCustomObject]$item
            } else {
                $item
            }
        }
        # Export to temp file, then rewrite without BOM
        $tempPath = "$Path.tmp"
        $converted | Export-Csv -Path $tempPath -Delimiter "`t" -NoTypeInformation -Encoding UTF8
        # Re-read and write without BOM
        $content = [System.IO.File]::ReadAllText($tempPath, [System.Text.Encoding]::UTF8)
        # Strip BOM if present
        if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
            $content = $content.Substring(1)
        }
        [System.IO.File]::WriteAllText($Path, $content, $global:Utf8NoBom)
        Remove-Item $tempPath -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Failed to export TSV to $Path : $_" -Level "ERROR"
        Remove-Item "$Path.tmp" -ErrorAction SilentlyContinue
    }
}
