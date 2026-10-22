[CmdletBinding()]
param(
    # 复用已有的 Release 构建产物，跳过 flutter build
    [switch]$SkipBuild,
    # 覆盖默认产物文件名（不含扩展名，默认 PIEBlock-<版本>-windows-portable）
    [string]$OutputBaseName = '',
    # csc.exe 路径，缺省时自动探测（Windows 自带的 .NET Framework 编译器）
    [string]$Csc = '',
    # 载荷压缩级别：Optimal 平衡体积与打包时间，Fastest 更快但体积略大
    [ValidateSet('Optimal', 'Fastest', 'NoCompression')]
    [string]$CompressionLevel = 'Optimal',
    # 打包后用 EXTRACT_ONLY 模式运行一次单 exe，校验解压结果
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$launcherSource = Join-Path $PSScriptRoot 'portable_launcher\PortableLauncher.cs'
$iconPath = Join-Path $repoRoot 'windows\runner\resources\app_icon.ico'
$outputDir = Join-Path $repoRoot 'output'

# --- 版本号：以 pubspec.yaml 为单一来源 ---
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)') {
    throw '无法从 pubspec.yaml 解析 version 行。'
}
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"

# --- 内置 SDCC 工具链前置检查：必须是 Windows 版，否则便携版无法编译固件 ---
$bundleManifest = Join-Path $repoRoot 'vendor\sdcc-toolchain\bundle_manifest.json'
if (!(Test-Path -LiteralPath $bundleManifest -PathType Leaf)) {
    throw '缺少内置 SDCC 工具链，请先运行 tools\prepare_sdcc_toolchain.ps1。'
}
$bundle = Get-Content -LiteralPath $bundleManifest -Raw | ConvertFrom-Json
if ($null -ne $bundle.platform -and $bundle.platform -ne 'windows-x64') {
    throw "内置 SDCC 工具链平台不是 windows-x64：$($bundle.platform)；请重新运行 tools\prepare_sdcc_toolchain.ps1 -Force。"
}
$sdccExe = Join-Path $repoRoot 'vendor\sdcc-toolchain\bin\sdcc.exe'
if (!(Test-Path -LiteralPath $sdccExe -PathType Leaf)) {
    throw "内置 SDCC 工具链缺少 bin\sdcc.exe，Windows 固件无法编译：$sdccExe（请重新运行 tools\prepare_sdcc_toolchain.ps1 -Force）"
}

# --- 定位 csc.exe（.NET Framework 4.x，Windows 10/11 自带）---
function Find-Csc {
    $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $framework32 = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    foreach ($candidate in @($frameworkRoot, $framework32)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $fromPath = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) { return $fromPath.Source }
    return $null
}
if ([string]::IsNullOrWhiteSpace($Csc)) {
    $Csc = Find-Csc
}
if ([string]::IsNullOrWhiteSpace($Csc) -or !(Test-Path -LiteralPath $Csc -PathType Leaf)) {
    throw '未找到 csc.exe（.NET Framework 4.x 编译器），请安装 .NET Framework 4.8 或用 -Csc 指定路径。'
}
if (!(Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
    throw "缺少便携版启动器源码：$launcherSource"
}
if (!(Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "缺少应用图标：$iconPath"
}

# --- Release 构建 ---
if (!$SkipBuild) {
    Push-Location $repoRoot
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

# --- Release 产物完整性校验：单 exe 必须包含工具链与固件模板，缺一不可 ---
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

# --- 打包：Release 目录 -> zip 载荷 -> 单 exe ---
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pieblock-portable-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $payloadZip = Join-Path $tempDir 'payload.zip'
    $zipLevel = switch ($CompressionLevel) {
        'Optimal' { [System.IO.Compression.CompressionLevel]::Optimal }
        'Fastest' { [System.IO.Compression.CompressionLevel]::Fastest }
        'NoCompression' { [System.IO.Compression.CompressionLevel]::NoCompression }
    }
    # includeBaseDirectory=false：Release 目录的内容必须位于 zip 根，解压后
    # PIE-Block.exe 直接落在缓存目录下；默认的 true 会多出一层 Release\。
    [System.IO.Compression.ZipFile]::CreateFromDirectory($releaseDir, $payloadZip, $zipLevel, $false)

    $hash = (Get-FileHash -LiteralPath $payloadZip -Algorithm SHA256).Hash.ToLowerInvariant()
    $payloadId = "$version-$($hash.Substring(0, 16))"
    $idFile = Join-Path $tempDir 'payload.id'
    [System.IO.File]::WriteAllText($idFile, $payloadId, (New-Object System.Text.UTF8Encoding($false)))

    if ([string]::IsNullOrWhiteSpace($OutputBaseName)) {
        $OutputBaseName = "PIEBlock-$version-windows-portable"
    }
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $targetExe = Join-Path $outputDir ($OutputBaseName + '.exe')

    $cscArgs = @(
        '/nologo',
        '/target:winexe',
        '/platform:anycpu',
        '/optimize+',
        '/codepage:65001',
        '/reference:System.Windows.Forms.dll',
        '/reference:System.IO.Compression.dll',
        '/reference:System.IO.Compression.FileSystem.dll',
        "/win32icon:$iconPath",
        "/out:$targetExe",
        "/resource:$payloadZip,payload.zip",
        "/resource:$idFile,payload.id",
        $launcherSource
    )
    & $Csc @cscArgs
    if ($LASTEXITCODE -ne 0) {
        throw "csc 编译单文件便携版失败，退出码: $LASTEXITCODE"
    }
    if (!(Test-Path -LiteralPath $targetExe -PathType Leaf)) {
        throw "未找到单文件便携版输出: $targetExe"
    }

    # --- 自检：用 EXTRACT_ONLY 模式跑一次，确认内嵌载荷能完整解压 ---
    # 自检用仓库 tmp 下的临时根目录（PIEBLOCK_PORTABLE_ROOT），不污染用户
    # 的 %LOCALAPPDATA% 缓存；同时避免无写权限环境干扰。
    if ($Verify) {
        $verifyRoot = Join-Path $repoRoot ("tmp\portable-verify-" + [guid]::NewGuid().ToString('N'))
        $verifyLog = Join-Path $verifyRoot 'launcher.log'
        New-Item -ItemType Directory -Force -Path $verifyRoot | Out-Null
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $targetExe
            $startInfo.UseShellExecute = $false
            $startInfo.EnvironmentVariables['PIEBLOCK_PORTABLE_ROOT'] = $verifyRoot
            $startInfo.EnvironmentVariables['PIEBLOCK_PORTABLE_EXTRACT_ONLY'] = '1'
            $startInfo.EnvironmentVariables['PIEBLOCK_PORTABLE_LOG'] = $verifyLog
            $process = [System.Diagnostics.Process]::Start($startInfo)
            if (!$process.WaitForExit(180000)) {
                try { $process.Kill() } catch { }
                throw '单文件便携版解压自检超时（180s）。'
            }
            if ($process.ExitCode -ne 0) {
                $detail = if (Test-Path -LiteralPath $verifyLog) {
                    (Get-Content -LiteralPath $verifyLog -Raw).Trim()
                }
                else { '（启动器未留下日志）' }
                throw "单文件便携版解压自检失败，退出码: $($process.ExitCode)`n$detail"
            }
            $cacheRoot = Join-Path $verifyRoot $payloadId
            foreach ($relative in $required) {
                if (!(Test-Path -LiteralPath (Join-Path $cacheRoot $relative))) {
                    throw "解压自检缺失文件: $relative（缓存目录: $cacheRoot）"
                }
            }
            Write-Host "[PASS] 解压自检: $cacheRoot"
        }
        finally {
            Remove-Item -LiteralPath $verifyRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $sizeMb = [math]::Round((Get-Item -LiteralPath $targetExe).Length / 1MB, 1)
    $zipMb = [math]::Round((Get-Item -LiteralPath $payloadZip).Length / 1MB, 1)
    Write-Host "[PASS] Windows 单文件便携版: $targetExe ($sizeMb MB，载荷 $zipMb MB，id $payloadId)"
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
