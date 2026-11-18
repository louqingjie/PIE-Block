[CmdletBinding()]
param(
    [switch]$NoMouse,
    [switch]$Demo
)

$ErrorActionPreference = 'Stop'
$repoTui = Split-Path -Parent $MyInvocation.MyCommand.Path

$cargoPath = $null
$command = Get-Command cargo -ErrorAction SilentlyContinue
if ($command) {
    $cargoPath = $command.Source
} else {
    $candidate = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    if (Test-Path -LiteralPath $candidate) {
        $cargoPath = $candidate
    }
}

if (-not $cargoPath) {
    Write-Error 'cargo not found. Install Rust from https://rustup.rs and reopen the terminal (PATH refresh).'
    exit 1
}

$forward = @()
if ($NoMouse) { $forward += '--no-mouse' }
if ($Demo) { $forward += '--demo' }

Push-Location $repoTui
try {
    & $cargoPath run -p pieblock-tui -- @forward
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
