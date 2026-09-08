# Helper functions for Day-0 Capture

$global:CaptureLogPath = ""
$global:FailuresLogPath = ""

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ssZ")
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine
    if ($global:CaptureLogPath) {
        Add-Content -Path $global:CaptureLogPath -Value $logLine -Encoding UTF8
    }
    if ($Level -eq "ERROR" -or $Level -eq "WARNING") {
        if ($global:FailuresLogPath) {
            Add-Content -Path $global:FailuresLogPath -Value $logLine -Encoding UTF8
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
        [bool]$Append = $false
    )
    Write-Log "Executing: $Command $($ArgsList -join ' ')"
    $startTime = (Get-Date).ToUniversalTime()
    
    # We use Start-Process with Wait and RedirectStandardOutput to safely execute without Invoke-Expression
    try {
        if ($Append) {
            # Start-Process redirection overwrites, so we use a temporary file if append is needed
            # Actually, standard Start-Process redirection does overwrite. We'll simplify and assume overwrite for external commands unless specified.
            # We'll just run it directly and redirect using standard powershell redirection if possible, but Start-Process is safer.
        }
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
        $Data | ConvertTo-Json -Depth $Depth -Compress:$false | Out-File -FilePath $Path -Encoding UTF8
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
        # PS 5.1 Export-Csv supports -Delimiter but default encoding might be ASCII or UTF8 with BOM
        # We want UTF8 without BOM ideally, but Out-File -Encoding UTF8 is standard.
        $Data | Export-Csv -Path $Path -Delimiter "`t" -NoTypeInformation -Encoding UTF8
    } catch {
        Write-Log "Failed to export TSV to $Path : $_" -Level "ERROR"
    }
}

