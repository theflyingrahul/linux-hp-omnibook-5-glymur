<#
.SYNOPSIS
Tests safe helper functions for Windows PowerShell 5.1 compatibility without
mutating the system or capturing real hardware data.
#>
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "helpers.ps1")

Write-Host "Running static tests..."

# Create a temp directory for test files
$testDir = Join-Path $env:TEMP "day0-test-$([guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

try {
    # Test Get-SafeProperty
    $testObj = [PSCustomObject]@{ Foo = "Bar" }
    $result = Get-SafeProperty $testObj 'Foo'
    if ($result -ne "Bar") { throw "Get-SafeProperty failed on valid object" }
    $result2 = Get-SafeProperty $null 'Foo'
    if ($null -ne $result2) { throw "Get-SafeProperty failed on null object" }
    Write-Host "  Get-SafeProperty: PASS"

    # Test JSON export (no BOM, valid JSON, array preservation)
    $jsonPath = Join-Path $testDir "test.json"
    $obj = @{ Test = "Value"; Nested = @{ Key = "Data" } }
    Export-SafeJson -Data $obj -Path $jsonPath
    if (-not (Test-Path $jsonPath)) { throw "JSON export failed to create file" }
    # Verify no BOM
    $bytes = [System.IO.File]::ReadAllBytes($jsonPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "JSON file has UTF-8 BOM"
    }
    Write-Host "  Export-SafeJson (object): PASS"

    # Test JSON array export
    $jsonArrPath = Join-Path $testDir "test-array.json"
    $arr = @( @{ A = "1"; B = "2" }, @{ A = "3"; B = "4" } )
    Export-SafeJson -Data $arr -Path $jsonArrPath
    $jsonContent = [System.IO.File]::ReadAllText($jsonArrPath)
    if (-not $jsonContent.TrimStart().StartsWith("[")) {
        throw "JSON array export did not produce array wrapper. Got: $($jsonContent.Substring(0, [Math]::Min(50, $jsonContent.Length)))"
    }
    Write-Host "  Export-SafeJson (array): PASS"

    # Test TSV export with hashtables (should convert to PSCustomObject)
    $tsvPath = Join-Path $testDir "test.tsv"
    $tsvData = @( @{ ColA = "1"; ColB = "2" }, @{ ColA = "3"; ColB = "4" } )
    Export-SafeTsv -Data $tsvData -Path $tsvPath
    if (-not (Test-Path $tsvPath)) { throw "TSV export failed to create file" }
    # Verify no BOM
    $tsvBytes = [System.IO.File]::ReadAllBytes($tsvPath)
    if ($tsvBytes.Length -ge 3 -and $tsvBytes[0] -eq 0xEF -and $tsvBytes[1] -eq 0xBB -and $tsvBytes[2] -eq 0xBF) {
        throw "TSV file has UTF-8 BOM"
    }
    # Verify column names are correct (not Count/Keys/Values)
    $tsvContent = [System.IO.File]::ReadAllText($tsvPath)
    if ($tsvContent -match "IsReadOnly") {
        throw "TSV export serialized hashtable metadata instead of key-value pairs"
    }
    if (-not ($tsvContent -match "ColA")) {
        throw "TSV export missing expected column name 'ColA'"
    }
    Write-Host "  Export-SafeTsv (hashtable array): PASS"

    # Test Write-Log (UTC timestamp)
    $global:CaptureLogPath = Join-Path $testDir "test.log"
    Write-Log "Test message"
    $logContent = [System.IO.File]::ReadAllText($global:CaptureLogPath)
    if (-not ($logContent -match "\[INFO\] Test message")) {
        throw "Write-Log output format incorrect"
    }
    Write-Host "  Write-Log: PASS"

    # Test Test-Elevated
    $elev = Test-Elevated
    if ($elev -isnot [bool]) { throw "Test-Elevated did not return bool" }
    Write-Host "  Test-Elevated: PASS"

    Write-Host "All static tests PASSED."

} finally {
    # Clean up
    $global:CaptureLogPath = ""
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
