<#
.SYNOPSIS
Tests safe helper functions for Windows PowerShell 5.1 compatibility without mutating the system or capturing real hardware data.
#>
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $ScriptDir "helpers.ps1")

Write-Host "Running static tests..."

# Test JSON
$obj = @{ Test = "Value"; Nested = @{ Key = "Data" } }
Export-SafeJson -Data $obj -Path "test.json"
if (-not (Test-Path "test.json")) { throw "JSON test failed" }
Remove-Item "test.json"

# Test TSV
$arr = @( @{ A="1"; B="2" }, @{ A="3"; B="4" } )
Export-SafeTsv -Data $arr -Path "test.tsv"
if (-not (Test-Path "test.tsv")) { throw "TSV test failed" }
Remove-Item "test.tsv"

Write-Host "All static tests PASSED."
