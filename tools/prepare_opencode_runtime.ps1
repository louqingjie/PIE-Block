[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lockPath = Join-Path $PSScriptRoot 'opencode_runtime.lock.json'
$licensePath = Join-Path $repoRoot 'docs\licenses\OpenCode-LICENSE.txt'
$stageRoot = Join-Path $repoRoot 'vendor\opencode-runtime'
$downloadRoot = Join-Path $repoRoot 'tmp\opencode-runtime-download'

if (!(Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "OpenCode 运行时锁定文件不存在: $lockPath"
}
if (!(Test-Path -LiteralPath $licensePath -PathType Leaf)) {
    throw "OpenCode 许可证文件不存在: $licensePath"
}
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
if ($lock.platform -ne 'windows' -or $lock.architecture -ne 'x86_64') {
    throw '当前准备脚本只接受 Windows x64 OpenCode 运行时。'
}

function Assert-WorkspacePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (!$full.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝操作工作区外路径: $full"
    }
    return $full
}

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

$stageRoot = Assert-WorkspacePath $stageRoot
$downloadRoot = Assert-WorkspacePath $downloadRoot
$manifestPath = Join-Path $stageRoot 'bundle_manifest.json'
if (!$Force -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $executable = Join-Path $stageRoot ([string]$manifest.executable)
    if ($manifest.version -eq $lock.version -and
            (Test-Path -LiteralPath $executable -PathType Leaf)) {
        $actual = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -eq [string]$lock.executable_sha256) {
            $reportedVersion = Get-OpenCodeVersion $executable `
                (Join-Path $downloadRoot 'version-check')
            if ($reportedVersion -ne [string]$lock.version) {
                throw "OpenCode 版本校验失败，期望 $($lock.version)，实际 $reportedVersion"
            }
            Write-Host "[PASS] OpenCode $($lock.version) 运行时已准备: $stageRoot"
            exit 0
        }
    }
}

foreach ($path in @($stageRoot, $downloadRoot)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$archive = Join-Path $downloadRoot ([string]$lock.asset_name)
$expanded = Join-Path $downloadRoot 'expanded'
Write-Host "正在下载 OpenCode $($lock.version) Windows x64…"
Invoke-WebRequest -Uri ([string]$lock.asset_url) -OutFile $archive -UseBasicParsing
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveHash -ne [string]$lock.archive_sha256) {
    throw "OpenCode 压缩包哈希不匹配: $archiveHash"
}

Expand-Archive -LiteralPath $archive -DestinationPath $expanded
$candidates = @(Get-ChildItem -LiteralPath $expanded -Filter 'opencode.exe' -File -Recurse)
if ($candidates.Count -ne 1) {
    throw "OpenCode 压缩包内应恰好包含一个 opencode.exe，实际为 $($candidates.Count) 个。"
}
$executableHash = (Get-FileHash -LiteralPath $candidates[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($executableHash -ne [string]$lock.executable_sha256) {
    throw "OpenCode 可执行文件哈希不匹配: $executableHash"
}

Copy-Item -LiteralPath $candidates[0].FullName -Destination (Join-Path $stageRoot 'opencode.exe')
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $stageRoot 'LICENSE.txt')
$licenseHash = (Get-FileHash -LiteralPath (Join-Path $stageRoot 'LICENSE.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
$bundle = [ordered]@{
    version = [string]$lock.version
    platform = [string]$lock.platform
    architecture = [string]$lock.architecture
    executable = 'opencode.exe'
    sha256 = $executableHash
    source_url = [string]$lock.asset_url
    source_repository = [string]$lock.source_repository
    archive_sha256 = [string]$lock.archive_sha256
    files = [ordered]@{
        'opencode.exe' = $executableHash
        'LICENSE.txt' = $licenseHash
    }
}
$bundle | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $manifestPath -Encoding utf8

$reportedVersion = Get-OpenCodeVersion (Join-Path $stageRoot 'opencode.exe') `
    (Join-Path $downloadRoot 'version-check')
if ($reportedVersion -ne [string]$lock.version) {
    throw "OpenCode 版本校验失败，期望 $($lock.version)，实际 $reportedVersion"
}
Remove-Item -LiteralPath $downloadRoot -Recurse -Force
Write-Host "[PASS] OpenCode $reportedVersion 运行时已准备: $stageRoot"
