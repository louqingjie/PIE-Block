[CmdletBinding()]
param(
    [string]$Godot = 'C:\Users\louqi\Desktop\program\Godot_v4.7.1-stable_mono_win64\godot.exe',
    [string]$Output = '',
    [switch]$ExportDebug
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bundleManifest = Join-Path $repoRoot 'vendor\sdcc-toolchain\bundle_manifest.json'
$opencodeManifest = Join-Path $repoRoot 'vendor\opencode-runtime\bundle_manifest.json'

function Get-OpenCodeVersion([string]$Executable, [string]$DataRoot) {
    foreach ($directory in @('config', 'data', 'cache', 'state')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DataRoot $directory) | Out-Null
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.ArgumentList.Add('--version')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['OPENCODE_DISABLE_AUTOUPDATE'] = 'true'
    $startInfo.Environment['XDG_CONFIG_HOME'] = Join-Path $DataRoot 'config'
    $startInfo.Environment['XDG_DATA_HOME'] = Join-Path $DataRoot 'data'
    $startInfo.Environment['XDG_CACHE_HOME'] = Join-Path $DataRoot 'cache'
    $startInfo.Environment['XDG_STATE_HOME'] = Join-Path $DataRoot 'state'
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd().Trim()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($stdout)) {
        throw "OpenCode 版本探测失败（退出码 $($process.ExitCode)）: $stderr"
    }
    return ($stdout -split "`r?`n" | Select-Object -Last 1).Trim()
}
if (!(Test-Path -LiteralPath $bundleManifest -PathType Leaf)) {
    throw '缺少内置 SDCC 工具链，请先运行 tools\prepare_sdcc_toolchain.ps1。'
}
if (!(Test-Path -LiteralPath $opencodeManifest -PathType Leaf)) {
    throw '缺少内置 OpenCode 运行时，请先运行 tools\prepare_opencode_runtime.ps1。'
}
if (!(Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot 不存在: $Godot"
}
$bundle = Get-Content -LiteralPath $bundleManifest -Raw | ConvertFrom-Json
foreach ($property in $bundle.files.PSObject.Properties) {
    $file = Join-Path (Split-Path -Parent $bundleManifest) $property.Name
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "SDCC 工具链文件缺失: $($property.Name)"
    }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$property.Value) {
        throw "SDCC 工具链哈希不匹配: $($property.Name)"
    }
}
$opencode = Get-Content -LiteralPath $opencodeManifest -Raw | ConvertFrom-Json
if ($opencode.platform -ne 'windows' -or $opencode.architecture -ne 'x86_64') {
    throw 'OpenCode 运行时不是 Windows x64 构建。'
}
foreach ($property in $opencode.files.PSObject.Properties) {
    $file = Join-Path (Split-Path -Parent $opencodeManifest) $property.Name
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "OpenCode 运行时文件缺失: $($property.Name)"
    }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$property.Value) {
        throw "OpenCode 运行时哈希不匹配: $($property.Name)"
    }
}
$opencodeExe = Join-Path (Split-Path -Parent $opencodeManifest) $opencode.executable
$reportedVersion = Get-OpenCodeVersion $opencodeExe (Join-Path $repoRoot 'tmp\opencode-version-check')
if ($reportedVersion -ne [string]$opencode.version) {
    throw "OpenCode 运行时版本不匹配，清单为 $($opencode.version)，实际为 $reportedVersion"
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $repoRoot 'output\PIEBlock_v_0_7.exe'
}
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
$mode = if ($ExportDebug) { '--export-debug' } else { '--export-release' }
$arguments = @('--headless', '--path', ('"' + $repoRoot + '"'), $mode,
    '"Windows Desktop"', ('"' + $Output + '"'))
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -NoNewWindow -PassThru
$process.WaitForExit()
if ($process.ExitCode -ne 0) {
    throw "Godot Windows 导出失败，退出码: $($process.ExitCode)"
}
$sidecar = [IO.Path]::ChangeExtension($Output, '.pck')
if (Test-Path -LiteralPath $sidecar) {
    throw "导出产生了旁置 PCK，不符合单文件要求: $sidecar"
}
Write-Host "[PASS] 单文件 Windows EXE: $Output"
