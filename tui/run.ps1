[CmdletBinding()]
param(
    [switch]$NoMouse,
    [switch]$Demo,
    [switch]$Diagnostics,
    [switch]$Version
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
if ($Diagnostics) { $forward += '--diagnostics' }
if ($Version) { $forward += '--version' }

Push-Location $repoTui
try {
    & $cargoPath run -p pieblock-tui -- @forward
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $running = Get-Process -Name 'pieblock-tui' -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host ''
            Write-Host '构建/启动失败：检测到仍有 pieblock-tui 进程在运行（Windows 会锁定 target\debug 下的 exe）。' -ForegroundColor Yellow
            Write-Host '请先退出正在运行的 TUI 窗口，再重新执行本脚本。' -ForegroundColor Yellow
        }
    }
    exit $code
} finally {
    Pop-Location
}
