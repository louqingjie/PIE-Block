param(
    [ValidateSet(0, 1)]
    [int]$ExpectedReleasePipeline = 0
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\flutter\flutter\bin\flutter.bat'
$dart = 'C:\flutter\flutter\bin\dart.bat'
$env:ANDROID_HOME = 'C:\android'
$env:ANDROID_SDK_ROOT = 'C:\android'

# 阶段对象缓存键变化后，必须让 CMake 重新 configure，否则 .so 会内嵌
# 上一版本的 stage-object 哈希。Release 构建前强制清除原生 CMake 缓存。
$nativeCmakeCache = Join-Path $repositoryRoot (
    'packages\pieblock_sdcc_native\android\.cxx'
)
if (Test-Path -LiteralPath $nativeCmakeCache) {
    Remove-Item -LiteralPath $nativeCmakeCache -Recurse -Force
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

Push-Location (Join-Path $repositoryRoot 'packages\pieblock_core')
try {
    Invoke-Checked { & $dart analyze } 'pieblock_core analyze 失败'
    Invoke-Checked { & $dart test } 'pieblock_core test 失败'
} finally { Pop-Location }

Push-Location (Join-Path $repositoryRoot 'packages\pieblock_toolchain')
try {
    Invoke-Checked { & $dart analyze } 'pieblock_toolchain analyze 失败'
    Invoke-Checked { & $dart test } 'pieblock_toolchain test 失败'
    $env:PIEBLOCK_RUN_SDCC_GOLDEN = '1'
    Invoke-Checked {
        & $dart test test/sdcc_windows_android_golden_test.dart
    } 'Windows SDCC 黄金矩阵失败'
} finally {
    Remove-Item Env:PIEBLOCK_RUN_SDCC_GOLDEN -ErrorAction SilentlyContinue
    Pop-Location
}

$appRoot = Join-Path $repositoryRoot 'apps\pieblock_app'
Push-Location $appRoot
try {
    Invoke-Checked { & $flutter analyze } 'Flutter analyze 失败'
    Invoke-Checked { & $flutter test } 'Flutter test 失败'
    Invoke-Checked { & $flutter build appbundle --release } 'Release AAB 构建失败'
} finally { Pop-Location }

$bundle = Join-Path $appRoot 'build\app\outputs\bundle\release\app-release.aab'
& (Join-Path $PSScriptRoot 'verify_android_package.ps1') `
    -PackagePath $bundle `
    -ExpectedPipelineEnabled $ExpectedReleasePipeline

Write-Output 'Android SDCC 无设备 CI 验收通过'
