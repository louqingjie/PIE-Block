# Batch screening helper: run stage-1 / stage-2 checks on several boards and append results to CSV.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnostics\run_screen_batch.ps1 -Stage 1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnostics\run_screen_batch.ps1 -Stage 2 -Port COM3
#
# For every board: swap the board, press Enter, the script runs the python checker and
# appends one row to the CSV (default: tools\diagnostics\screen_results.csv).
# Type q + Enter to stop.
#
# Notes: ASCII-only on purpose (Windows PowerShell 5.1 parses UTF-8 without BOM as ANSI).
[CmdletBinding()]
param(
    [ValidateSet('1', '2')]
    [string]$Stage = '1',
    [string]$Port = 'COM3',
    [string]$Csv = '',
    [string]$BoardPrefix = 'B',
    [int]$StartIndex = 1,
    [string]$Python = ''
)

$ErrorActionPreference = 'Stop'

$diagnosticsDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $diagnosticsDir)

if ([string]::IsNullOrWhiteSpace($Csv)) {
    $Csv = Join-Path $diagnosticsDir 'screen_results.csv'
}
if ([string]::IsNullOrWhiteSpace($Python)) {
    $Python = Join-Path $repoRoot '.venv\Scripts\python.exe'
}
if (-not (Test-Path $Python)) { throw "python not found: $Python (use -Python to point at it)" }

if ($Stage -eq '1') {
    $script = Join-Path $diagnosticsDir 'board_clock_screen.py'
    $stageName = 'stage1_app_baud'
}
else {
    $script = Join-Path $diagnosticsDir 'board_clock_probe_report.py'
    $stageName = 'stage2_probe'
}
if (-not (Test-Path $script)) { throw "checker not found: $script" }

if (-not (Test-Path $Csv)) {
    'board,date,stage,verdict,exit_code,estimated_clock_mhz,chipid15,chipid23,reason' |
        Set-Content -LiteralPath $Csv -Encoding UTF8
}

$index = $StartIndex
while ($true) {
    $board = '{0}{1:000}' -f $BoardPrefix, $index
    Write-Host ''
    Write-Host ('=== board ' + $board + ' : connect it, power it up, then press Enter (q to quit) ===')
    $answer = Read-Host
    if ($answer -eq 'q') { break }

    $json = Join-Path $env:TEMP ('screen_' + $board + '_' + $stageName + '.json')
    & $Python $script $Port --json $json
    $code = $LASTEXITCODE

    $verdict = 'WARN'
    $clock = ''
    $cid15 = ''
    $cid23 = ''
    $reason = ''
    if (Test-Path $json) {
        $obj = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $verdict = [string]$obj.verdict
        $reason = ([string]$obj.reason) -replace '"', "'" -replace "`r?`n", ' '
        if ($null -ne $obj.estimated_clock_mhz) { $clock = [string]$obj.estimated_clock_mhz }
        if ($null -ne $obj.chipid15) { $cid15 = ('0x{0:X2}' -f [int]$obj.chipid15) }
        if ($null -ne $obj.chipid23) { $cid23 = ('0x{0:X2}' -f [int]$obj.chipid23) }
    }
    $row = '{0},{1},{2},{3},{4},{5},{6},{7},"{8}"' -f `
        $board, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $stageName, $verdict, $code, $clock, $cid15, $cid23, $reason
    Add-Content -LiteralPath $Csv -Value $row -Encoding UTF8
    Write-Host ('--> recorded: ' + $board + ' ' + $verdict + ' (exit ' + $code + ')')
    $index++
}

Write-Host ('CSV: ' + $Csv)
