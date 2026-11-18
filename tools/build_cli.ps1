[CmdletBinding()]
param(
    # 目标平台：windows-x64 或 linux-x64，决定产物文件名与缺省输出目录
    [ValidateSet('windows-x64', 'linux-x64')]
    [string]$Target = 'windows-x64',
    # 输出目录；缺省时按目标平台放入对应 Release 的 cli 子目录
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cliSource = Join-Path $repoRoot 'packages\pieblock_core\bin\pieblock.dart'

if (!(Test-Path -LiteralPath $cliSource -PathType Leaf)) {
    throw "找不到 CLI 源码：$cliSource"
}

# dart compile exe 只能产出当前主机的可执行文件，不能交叉编译；Linux 包由
# package_flutter_linux.sh 在 Linux 上构建，这里拦下在错误主机上的调用。
$onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
$onLinux = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Linux)
if (($Target -eq 'windows-x64' -and !$onWindows) -or ($Target -eq 'linux-x64' -and !$onLinux)) {
    throw "dart compile exe 只能生成当前主机的产物，无法交叉编译 $Target。"
}

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw '找不到 dart 命令：构建独立 CLI 需要 Flutter/Dart SDK（打包机需先安装）。'
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = switch ($Target) {
        'windows-x64' { Join-Path $repoRoot 'build/windows/x64/runner/Release/cli' }
        'linux-x64' { Join-Path $repoRoot 'build/linux/x64/release/bundle/cli' }
    }
}
elseif (![System.IO.Path]::IsPathRooted($OutDir)) {
    # 统一成绝对路径：下面会 Push-Location 到包目录，相对路径会跟着漂移。
    $OutDir = Join-Path $repoRoot $OutDir
}

$exeName = switch ($Target) {
    'windows-x64' { 'pieblock-cli.exe' }
    'linux-x64' { 'pieblock-cli' }
}
$targetExe = Join-Path $OutDir $exeName

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Push-Location (Join-Path $repoRoot 'packages/pieblock_core')
try {
    & dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'dart pub get 失败。' }
    & dart compile exe bin/pieblock.dart -o $targetExe
    if ($LASTEXITCODE -ne 0) { throw 'dart compile exe 失败。' }
}
finally {
    Pop-Location
}

if (!(Test-Path -LiteralPath $targetExe -PathType Leaf)) {
    throw "未找到 CLI 产物：$targetExe"
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $targetExe).Length / 1MB, 1)
Write-Host "[PASS] 独立 CLI: $targetExe ($sizeMb MB)"
