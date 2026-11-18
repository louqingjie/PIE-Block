[CmdletBinding()]
param(
    [switch]$NoMouse
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

Push-Location $repoTui
try {
    if ($NoMouse) {
        & $cargoPath run -p pieblock-tui -- --no-mouse
    } else {
        & $cargoPath run -p pieblock-tui
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
