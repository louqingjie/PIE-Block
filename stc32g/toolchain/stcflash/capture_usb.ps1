# capture_usb.ps1 - USBPcap capture helper for STC32G USB-HID ISP.
# Run in an ELEVATED PowerShell (admin required for USBPcap).
#
# Modes:
#   .\capture_usb.ps1 -Detect            find which USBPcap device has the STC board (VID 34BF)
#   .\capture_usb.ps1 -Capture -Device 1 -Out capture.pcap
#                                         capture from USBPcapN; do the AiCube-ISP flash, then press Enter
#   .\capture_usb.ps1 -Capture -Device 1 -Out capture.pcap -Seconds 20
#                                         capture for 20 seconds automatically (do the flash during it)
param(
    [switch]$Detect,
    [switch]$Capture,
    [int]$Device = 1,
    [string]$Out = "capture.pcap",
    [int]$Seconds = 0
)

$ErrorActionPreference = "Stop"
$USBPcap = "C:\Program Files\USBPcap\USBPcapCMD.exe"

# venv python relative to this script: <workspace>/.venv/Scripts/python.exe
$Py = Join-Path $PSScriptRoot "..\..\..\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { $Py = "python" }
$ScanPy = Join-Path $PSScriptRoot "usbcap_scan.py"

if (-not (Test-Path $USBPcap)) {
    Write-Host "USBPcapCMD not found at $USBPcap"
    exit 1
}

$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WARNING: not elevated. USBPcap requires admin. Re-run from an admin PowerShell."
}

function Capture-Short([int]$n, [string]$tag) {
    # run USBPcapCMD for ~2.5s, return pcap path (may be empty/nonexistent)
    $dev = "\\.\USBPcap$n"
    $tmp = Join-Path $env:TEMP ("usbcap_${tag}_${n}.pcap")
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $p = Start-Process -FilePath $USBPcap -ArgumentList @("-d", $dev, "-o", $tmp, "-A", "--inject-descriptors") -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 2500
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Start-Sleep -Milliseconds 300
    return $tmp
}

if ($Detect) {
    Write-Host "Scanning USBPcap devices 1..8 for STC board (VID 0x34BF)..."
    $found = @()
    for ($n = 1; $n -le 8; $n++) {
        $tmp = Capture-Short $n "detect"
        if (-not (Test-Path $tmp)) { continue }
        $sz = (Get-Item $tmp).Length
        if ($sz -le 24) {
            Write-Host "  USBPcap${n}: exists but empty capture ($sz bytes) - hub with no traffic or needs admin"
            continue
        }
        Write-Host "  USBPcap${n}: $sz bytes, scanning for 34bf..."
        $out = & $Py $ScanPy $tmp 2>&1 | Out-String
        Write-Host ($out.Trim())
        if ($out -match "34bf") {
            Write-Host "  >>> STC board found on USBPcap$n"
            $found += $n
        }
    }
    if ($found.Count -gt 0) {
        Write-Host ""
        Write-Host ("STC board on USBPcap device(s): " + ($found -join ", "))
        Write-Host "Use: .\capture_usb.ps1 -Capture -Device <N> -Out cap.pcap"
    } else {
        Write-Host "No USBPcap device shows the STC board. Check the board is plugged in and you are elevated."
    }
    exit 0
}

if ($Capture) {
    $dev = "\\.\USBPcap$Device"
    $outAbs = Join-Path (Get-Location) $Out
    if (-not $outAbs.EndsWith(".pcap")) { $outAbs += ".pcap" }
    if (Test-Path $outAbs) { Remove-Item $outAbs -Force }
    Write-Host "Capturing from $dev to $outAbs ..."
    $p = Start-Process -FilePath $USBPcap -ArgumentList @("-d", $dev, "-o", $outAbs, "-A", "--inject-descriptors") -PassThru -WindowStyle Hidden
    if ($Seconds -gt 0) {
        Write-Host "Capture running for $Seconds seconds. NOW do the AiCube-ISP flash..."
        Start-Sleep -Seconds $Seconds
    } else {
        Write-Host "Capture running. NOW do the AiCube-ISP flash (one full download)."
        Write-Host "When done, press Enter to stop capture..."
        Read-Host | Out-Null
    }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Start-Sleep -Milliseconds 300
    if (Test-Path $outAbs) {
        Write-Host "Capture saved to $outAbs ($((Get-Item $outAbs).Length) bytes)"
    } else {
        Write-Host "Capture FAILED - no file produced (were you elevated?)"
    }
    exit 0
}

Write-Host "Usage: -Detect | -Capture -Device N -Out file [-Seconds S]"
