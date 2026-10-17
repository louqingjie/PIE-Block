# 以“正常权限”（Medium 完整性级别）在本机运行 Windows 桌面版，并保留 flutter run 的热重载。
#
# 背景：仓库目录可能被 AI agent 沙箱打过 Low 完整性标签（S-1-16-4096）。位于其中的
# PIE-Block.exe 会被 Windows 以 Low 进程启动，导致：
#   - flutter run（debug）的 DevFS 写不了 %TEMP%，直接崩在 _createDevFS；
#   - app 只能写仓库内目录，保存 .pieproj 到桌面/文档会报“拒绝访问”。
# 本脚本先把 build\windows 下的构建产物（含 exe）重新标记为 Medium 完整性级别
# （目录属主即可操作，不需要管理员），再执行 flutter run，让 app 以正常权限启动。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\run_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_windows.ps1 --release
#   powershell -ExecutionPolicy Bypass -File tools\run_windows.ps1 --profile --verbose
# 其余参数原样传给 flutter run；默认补上 -d windows。
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$windowsBuild = Join-Path $repoRoot 'build\windows\x64'
$runnerDir = Join-Path $windowsBuild 'runner'

# 给路径打 Medium 完整性标签；带继承标记，之后新生成的构建产物会自动继承。
function Set-MediumIntegrity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Recurse
    )
    if (!(Test-Path -LiteralPath $Path)) { return }
    $icaclsArgs = @($Path, '/setintegritylevel', '(OI)(CI)Medium')
    if ($Recurse) { $icaclsArgs += '/T' }
    $output = & icacls @icaclsArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "设置完整性级别失败：$Path（icacls 退出码 $LASTEXITCODE）`n$output"
    }
}

# 先确保目录存在并继承 Medium，再对已有产物递归修正：flutter run 重新构建
# 出来的 exe 会落在 runner 下，父目录已是 Medium，因此新文件自动是 Medium。
$null = New-Item -ItemType Directory -Force -Path $windowsBuild
$null = New-Item -ItemType Directory -Force -Path $runnerDir
Set-MediumIntegrity -Path $windowsBuild
Set-MediumIntegrity -Path $runnerDir
Set-MediumIntegrity -Path $runnerDir -Recurse
foreach ($mode in 'Debug', 'Profile', 'Release') {
    Set-MediumIntegrity -Path (Join-Path $runnerDir $mode) -Recurse
}

$deviceArgs = @()
$hasDeviceArg = @($FlutterArgs | Where-Object { $_ -in @('-d', '--device-id') }).Count -gt 0
if (!$hasDeviceArg) { $deviceArgs = @('-d', 'windows') }

Write-Host '[run_windows] 构建产物已标记为 Medium 完整性级别，开始 flutter run ...' -ForegroundColor Cyan
Push-Location $repoRoot
try {
    & flutter run @deviceArgs @FlutterArgs
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $exitCode
