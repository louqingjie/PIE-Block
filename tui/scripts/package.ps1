# 打包 PIE-Block TUI（Windows x64）
#
# 用法：
#   pwsh -File tui/scripts/package.ps1                 # 构建 release 并打包
#   pwsh -File tui/scripts/package.ps1 -SkipBuild      # 复用已构建的 release 产物
#   pwsh -File tui/scripts/package.ps1 -Version 0.2.0
#
# 产物：dist/PIE-Block-TUI-<版本>-windows-x64.zip + .sha256
param(
    [string]$Version = "",
    [switch]$SkipBuild,
    [string]$OutputRoot = ""
)
$ErrorActionPreference = "Stop"

$TuiRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $TuiRoot
if (-not $OutputRoot) { $OutputRoot = Join-Path $TuiRoot "dist" }

$CargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path $CargoBin) { $env:Path = "$CargoBin;$env:Path" }

if (-not $Version) {
    $cargoToml = Get-Content -Raw (Join-Path $TuiRoot "Cargo.toml")
    $match = [regex]::Match($cargoToml, '(?m)^version\s*=\s*"([^"]+)"')
    if (-not $match.Success) { throw "无法从 tui/Cargo.toml 读取版本号" }
    $Version = $match.Groups[1].Value
}

Write-Host "==> PIE-Block TUI $Version（windows-x64）打包"
if (-not $SkipBuild) {
    & cargo build --release -p pieblock-tui --manifest-path (Join-Path $TuiRoot "Cargo.toml")
    if ($LASTEXITCODE -ne 0) { throw "release 构建失败" }
}
$Exe = Join-Path $TuiRoot "target\release\pieblock-tui.exe"
if (-not (Test-Path $Exe)) { throw "找不到 release 产物：$Exe（请先构建）" }

$StageName = "PIE-Block-TUI-$Version-windows-x64"
$Stage = Join-Path $OutputRoot $StageName
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Path $Stage -Force | Out-Null

Copy-Item $Exe (Join-Path $Stage "pieblock-tui.exe")
Copy-Item (Join-Path $TuiRoot "README.md") (Join-Path $Stage "README.md")

# 运行时资源：可执行文件旁的 data/pieblock_runtime/ 会被自动定位。
$Runtime = Join-Path $Stage "data\pieblock_runtime"
New-Item -ItemType Directory -Path $Runtime -Force | Out-Null
Copy-Item (Join-Path $RepoRoot "vendor\sdcc-toolchain") (Join-Path $Runtime "sdcc-toolchain") -Recurse
Copy-Item (Join-Path $RepoRoot "stc32g_sdcc") (Join-Path $Runtime "stc32g_sdcc") -Recurse
$Templates = Join-Path $Stage "assets\templates"
New-Item -ItemType Directory -Path $Templates -Force | Out-Null
Copy-Item (Join-Path $RepoRoot "assets\templates\*") $Templates -Recurse

$Notice = @(
    "PIE-Block TUI 发布包第三方组件声明",
    "",
    "本发布包包含 SDCC（C251 版）工具链，位于 data/pieblock_runtime/sdcc-toolchain。",
    "SDCC 以其原始许可证（GPL）发布，许可证原文见 sdcc-toolchain/COPYING 与 COPYING3。",
    "stc32g_sdcc/ 为项目自带固件支撑源码，随本仓库许可证发布。",
    ""
) -join [Environment]::NewLine
Set-Content -Path (Join-Path $Stage "THIRD_PARTY_NOTICES.txt") -Value $Notice -Encoding utf8

# 校验：发布产物中不得出现 Dart/Flutter 运行时文件。
$forbidden = @()
$forbidden += Get-ChildItem -Path $Stage -Recurse -File | Where-Object {
    $_.Extension -in @(".dart", ".dill", ".so", ".dylib") -or
    $_.Name -like "flutter_*" -or $_.Name -like "libapp*" -or $_.Name -eq "libflutter*"
}
if ($forbidden.Count -gt 0) {
    $forbidden | Select-Object -First 20 | ForEach-Object { Write-Host "  [禁止] $($_.FullName)" }
    throw "发布产物包含 Dart/Flutter 文件，打包中止"
}
$dartDirs = Get-ChildItem -Path $Stage -Recurse -Directory | Where-Object {
    $_.Name -in @("flutter", "dart-sdk", ".dart_tool")
}
if ($dartDirs) { throw "发布产物包含 Dart/Flutter 目录" }

# 自检：从无关目录启动，解压态可执行文件应自行定位包内运行时资源。
Write-Host "==> 自检发布包运行环境…"
Push-Location $env:TEMP
try {
    $diag = & (Join-Path $Stage "pieblock-tui.exe") --diagnostics
    if ($LASTEXITCODE -ne 0) { throw "发布包 --diagnostics 自检失败" }
} finally {
    Pop-Location
}
$diagText = ($diag -join [Environment]::NewLine)
$Runtime = Join-Path $Stage "data\pieblock_runtime"
if (-not $diagText.Contains($Runtime)) { throw "发布包未定位到自身运行时资源：`n$diagText" }
$diag | ForEach-Object { Write-Host "    $_" }

$Zip = Join-Path $OutputRoot "$StageName.zip"
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $Zip -CompressionLevel Optimal
$Hash = (Get-FileHash -Algorithm SHA256 -Path $Zip).Hash.ToLowerInvariant()
Set-Content -Path "$Zip.sha256" -Value "$Hash  $StageName.zip" -Encoding ascii

$ZipSize = "{0:N1} MB" -f ((Get-Item $Zip).Length / 1MB)
$StageSize = "{0:N1} MB" -f ((Get-ChildItem $Stage -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "==> 完成：$Zip（$ZipSize，解压后 $StageSize）"
Write-Host "==> SHA-256：$Hash"
