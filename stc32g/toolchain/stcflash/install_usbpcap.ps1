# install_usbpcap.ps1 - Install/repair USBPcap driver (admin, reboot required).
# Usage: right-click -> Run with PowerShell (Admin), or:
#   powershell -ExecutionPolicy Bypass -File .\install_usbpcap.ps1
#
# USBPcap.inf uses the legacy DefaultInstall section (no Manufacturer/Models),
# so pnputil cannot install it. Must run InstallHinfSection DefaultInstall 132.
# It: copies USBPcap.sys, registers the kernel service, adds USBPcap to the
# USB class UpperFilters. Reboot is required for the filter to attach.

$ErrorActionPreference = "Stop"

$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: admin required. Right-click this script -> Run with PowerShell (Admin)."
    exit 1
}

$inf = "C:\Program Files\USBPcap\USBPcap.inf"
if (-not (Test-Path $inf)) {
    Write-Host "ERROR: $inf not found"
    exit 1
}

Write-Host "== Installing USBPcap.inf (DefaultInstall) =="
# 132 = 0x84: force + non-interactive install
& rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 132 $inf
Write-Host "rundll32 returned: $LASTEXITCODE"

Start-Sleep -Milliseconds 1500

Write-Host ""
Write-Host "== Verify service =="
Get-Service USBPcap -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType

Write-Host ""
Write-Host "== Verify driver registered =="
pnputil /enum-drivers | Select-String -Pattern "USBPcap" -Context 0,3

Write-Host ""
Write-Host "======================================================"
Write-Host "Install done. **PLEASE REBOOT** so UpperFilters take effect."
Write-Host "After reboot you should see \\.\USBPcap1 etc. devices."
Write-Host "Then run: .\capture_usb.ps1 -Detect"
Write-Host "======================================================"
