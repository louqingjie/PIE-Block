[CmdletBinding()]
param(
    [string]$MsysRoot = 'C:\msys64',
    [switch]$Force,
    [switch]$PackageOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = (Resolve-Path (Join-Path $repoRoot 'sdcc-c251')).Path
$stageRoot = Join-Path $repoRoot 'vendor\sdcc-toolchain'
$buildRoot = Join-Path $repoRoot 'tmp\pie-block-sdcc-windows-build'
$installRoot = Join-Path $repoRoot 'tmp\pie-block-sdcc-windows-install'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'

if (!(Test-Path -LiteralPath $bash -PathType Leaf)) {
    throw "未找到 MSYS2 bash: $bash"
}
if (!$Force -and (Test-Path -LiteralPath (Join-Path $stageRoot 'bundle_manifest.json'))) {
    Write-Host 'SDCC 工具链已准备；如需重建请加 -Force。'
    exit 0
}

foreach ($path in @($stageRoot, $buildRoot, $installRoot)) {
    $full = [IO.Path]::GetFullPath($path)
    if (!$full.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝清理工作区外路径: $full"
    }
    $shouldClean = $full.Equals([IO.Path]::GetFullPath($stageRoot),
        [StringComparison]::OrdinalIgnoreCase) -or !$PackageOnly
    if ($shouldClean -and (Test-Path -LiteralPath $full)) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

function To-MsysPath([string]$Path) {
    $result = & $bash -lc 'cygpath -u "$1"' _ $Path
    if ($LASTEXITCODE -ne 0) { throw "cygpath 转换失败: $Path" }
    return ($result | Select-Object -Last 1).Trim()
}

if (!$PackageOnly) {
    $buildScript = To-MsysPath (Join-Path $PSScriptRoot 'build_sdcc_windows_package.sh')
    $sourcePosix = To-MsysPath $sourceRoot
    $buildPosix = To-MsysPath $buildRoot
    $installPosix = To-MsysPath $installRoot
    $buildArguments = @($buildScript, $sourcePosix, $buildPosix, $installPosix)
    & $bash @buildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "SDCC Windows 工具链构建失败，退出码: $LASTEXITCODE"
    }
}

$installed = Join-Path $installRoot 'sdcc'
if (!(Test-Path -LiteralPath $installed -PathType Container)) {
    throw "SDCC 安装目录不存在: $installed"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stageRoot) | Out-Null
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'bin') | Out-Null
foreach ($binary in @('sdcc.exe', 'sdcpp.exe', 'sdas251.exe', 'sdld.exe')) {
    Copy-Item -LiteralPath (Join-Path $installed "bin\$binary") `
        -Destination (Join-Path $stageRoot 'bin')
}
Copy-Item -LiteralPath (Join-Path $installed 'include') -Destination $stageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $installed 'libexec') -Destination $stageRoot -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'lib') | Out-Null
Copy-Item -LiteralPath (Join-Path $installed 'lib\mcs251-large-stack-auto') `
    -Destination (Join-Path $stageRoot 'lib') -Recurse
Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $sourceRoot 'COPYING') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $sourceRoot 'sdas\COPYING3') -Destination $stageRoot

$required = @(
    'bin\sdcc.exe', 'bin\sdcpp.exe', 'bin\sdas251.exe', 'bin\sdld.exe',
    'include\mcs51\mcs51reg.h',
    'libexec\sdcc\x86_64-pc-mingw64\12.1.0\cc1.exe',
    'lib\mcs251-large-stack-auto\mcs251.lib',
    'lib\mcs251-large-stack-auto\libsdcc.lib'
)
foreach ($relative in $required) {
    if (!(Test-Path -LiteralPath (Join-Path $stageRoot $relative) -PathType Leaf)) {
        throw "SDCC 工具链缺少必要文件: $relative"
    }
}

$commit = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
    throw '无法读取 sdcc-c251 子模块提交。'
}
$hashes = [ordered]@{}
Get-ChildItem -LiteralPath $stageRoot -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($stageRoot, $_.FullName).Replace('\', '/')
        $hashes[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
$bundle = [ordered]@{
    version = $commit
    source_repository = 'https://github.com/louqingjie/sdcc-c251.git'
    source_commit = $commit
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    files = $hashes
}
$bundle | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $stageRoot 'bundle_manifest.json') -Encoding utf8

& (Join-Path $stageRoot 'bin\sdcc.exe') --version
if ($LASTEXITCODE -ne 0) { throw '准备后的 sdcc.exe 无法运行。' }
Write-Host "[PASS] SDCC 工具链已准备: $stageRoot"
