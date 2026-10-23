# Build the "clock self-test probe" firmware (Keil C251) from the repo's stc32g tree.
#
# Usage (works in Windows PowerShell 5.1 and PowerShell 7):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnostics\build_clock_probe.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnostics\build_clock_probe.ps1 -OutHex D:\tmp\probe.hex
#
# Output: tools\diagnostics\clock_probe_keil.hex by default (*.hex is gitignored).
#
# Notes:
#   - The probe source is clock_probe_main.c in this directory;
#   - The script copies stc32g/Libraries and stc32g/Projects/ROBOMASTER_INFANTRY to a temp
#     directory, overwrites USER/src/main.c with the probe source, then runs UV4 -r there.
#     It never modifies files inside the repository.
#   - This script is intentionally ASCII-only so it parses under Windows PowerShell 5.1.
[CmdletBinding()]
param(
    [string]$KeilRoot = 'C:\Keil_v5',
    [string]$OutHex = '',
    [switch]$KeepWork
)

$ErrorActionPreference = 'Stop'

$diagnosticsDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $diagnosticsDir)
$uv4 = Join-Path $KeilRoot 'UV4\UV4.exe'
$srcTree = Join-Path $repoRoot 'stc32g'
$probeSrc = Join-Path $diagnosticsDir 'clock_probe_main.c'

if (-not (Test-Path $uv4)) { throw "UV4 not found: $uv4 (use -KeilRoot to point at your Keil install)" }
if (-not (Test-Path $srcTree)) { throw "stc32g directory not found: $srcTree" }
if (-not (Test-Path $probeSrc)) { throw "probe source not found: $probeSrc" }
if ([string]::IsNullOrWhiteSpace($OutHex)) {
    $OutHex = Join-Path $diagnosticsDir 'clock_probe_keil.hex'
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('pie_clock_probe_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ws = Join-Path $work 'stc32g'
New-Item -ItemType Directory -Path $ws -Force | Out-Null

Write-Host "[1/4] copying project tree -> $ws"
& robocopy (Join-Path $srcTree 'Libraries') (Join-Path $ws 'Libraries') /E /NFL /NDL /NJH /NJS /NP | Out-Null
& robocopy (Join-Path $srcTree 'Projects\ROBOMASTER_INFANTRY') (Join-Path $ws 'Projects\ROBOMASTER_INFANTRY') /E /XD Objects Listings /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copy failed, robocopy exit code $LASTEXITCODE" }

$projectDir = Join-Path $ws 'Projects\ROBOMASTER_INFANTRY'
$mdk = Join-Path $projectDir 'MDK'
$mainDst = Join-Path $projectDir 'USER\src\main.c'
Write-Host "[2/4] writing probe main.c -> $mainDst"
Copy-Item $probeSrc $mainDst -Force

Write-Host "[3/4] running Keil UV4 rebuild..."
Push-Location $mdk
try {
    $log = Join-Path $mdk 'build_probe.log'
    & $uv4 -r 'Project_Template.uvproj' -o $log | Out-Null
    $uvExit = $LASTEXITCODE
    if (Test-Path $log) {
        Get-Content $log | Select-Object -Last 10 | ForEach-Object { "    $_" }
    }
    if (-not (Select-String -Path $log -Pattern '0 Error\(s\)' -Quiet)) {
        throw "Keil build failed (UV4 exit code $uvExit); log: $log"
    }
}
finally {
    Pop-Location
}

$hex = Join-Path $mdk 'Objects\Project_Template.hex'
if (-not (Test-Path $hex)) { throw "hex not generated: $hex" }

$outDir = Split-Path -Parent $OutHex
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
Copy-Item $hex $OutHex -Force
$sha = (Get-FileHash $OutHex -Algorithm SHA256).Hash
Write-Host "[4/4] done: $OutHex"
Write-Host "      SHA256: $sha"

if (-not $KeepWork) {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    Write-Host "      (work dir kept: $work)"
}
