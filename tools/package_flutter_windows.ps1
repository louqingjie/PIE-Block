[CmdletBinding()]
param(
    # 复用已有的 Release 构建产物，跳过 flutter build
    [switch]$SkipBuild,
    # 覆盖默认安装包文件名（不含扩展名，默认 PIEBlock-<版本>-windows-setup）
    [string]$OutputBaseName = '',
    # ISCC.exe 路径，缺省时自动探测
    [string]$Iscc = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$installerIss = Join-Path $repoRoot 'windows\installer\pieblock.iss'

# --- 版本号：以 pubspec.yaml 为单一来源 ---
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)') {
    throw '无法从 pubspec.yaml 解析 version 行。'
}
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"

# --- 内置 SDCC 工具链前置检查 ---
$bundleManifest = Join-Path $repoRoot 'vendor\sdcc-toolchain\bundle_manifest.json'
if (!(Test-Path -LiteralPath $bundleManifest -PathType Leaf)) {
    throw '缺少内置 SDCC 工具链，请先运行 tools\prepare_sdcc_toolchain.ps1。'
}

# --- 定位 ISCC.exe ---
function Find-Iscc {
    $candidates = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $fromPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) { return $fromPath.Source }
    return $null
}
if ([string]::IsNullOrWhiteSpace($Iscc)) {
    $Iscc = Find-Iscc
}
if ([string]::IsNullOrWhiteSpace($Iscc) -or !(Test-Path -LiteralPath $Iscc -PathType Leaf)) {
    throw '未找到 ISCC.exe，请安装 Inno Setup 6 或用 -Iscc 指定路径。'
}

# --- Release 构建 ---
if (!$SkipBuild) {
    Push-Location $appRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败。' }
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release 失败。' }
    }
    finally {
        Pop-Location
    }
}

# --- Release 产物完整性校验：不能只拷 exe，工具链与固件模板必须齐全 ---
$required = @(
    'PIE-Block.exe',
    'pieblock_hid.dll',
    'flutter_windows.dll',
    'data\icudtl.dat',
    'data\flutter_assets',
    'data\pieblock_runtime\sdcc-toolchain\bundle_manifest.json',
    'data\pieblock_runtime\stc32g_sdcc',
    'data\pieblock_runtime\stc32g\Libraries'
)
foreach ($relative in $required) {
    if (!(Test-Path -LiteralPath (Join-Path $releaseDir $relative))) {
        throw "Release 产物缺失: $relative（请勿跳过构建，或检查 CMake install 配置）"
    }
}

# --- 生成安装包 ---
if ([string]::IsNullOrWhiteSpace($OutputBaseName)) {
    $OutputBaseName = "PIEBlock-$version-windows-setup"
}
& $Iscc "/DAppVersion=$version" "/DOutputBaseName=$OutputBaseName" $installerIss
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup 编译失败，退出码: $LASTEXITCODE"
}
$setup = Join-Path $repoRoot "output\$OutputBaseName.exe"
if (!(Test-Path -LiteralPath $setup -PathType Leaf)) {
    throw "未找到安装包输出: $setup"
}
Write-Host "[PASS] Windows 安装包: $setup"
