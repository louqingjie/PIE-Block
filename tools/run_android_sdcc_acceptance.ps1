param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$ExpectedAbi,

    [ValidateRange(1, 100)]
    [int]$StabilityIterations = 100,

    [ValidateRange(1, 10)]
    [int]$FullBuildRepetitions = 1,

    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repositoryRoot 'apps\pieblock_app'
$flutter = 'C:\flutter\flutter\bin\flutter.bat'
$adb = 'C:\android\platform-tools\adb.exe'
$env:ANDROID_HOME = 'C:\android'
$env:ANDROID_SDK_ROOT = 'C:\android'

# 阶段对象变更后必须让 CMake 重新 configure，否则 .so 内嵌旧 stage-object
# 哈希，真机使用的是旧编译器产物。
$nativeCmakeCache = Join-Path $repositoryRoot (
    'packages\pieblock_sdcc_native\android\.cxx'
)
if (Test-Path -LiteralPath $nativeCmakeCache) {
    Remove-Item -LiteralPath $nativeCmakeCache -Recurse -Force
}

if (!(Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw "Flutter executable not found: $flutter"
}
if (!(Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw "ADB executable not found: $adb"
}

$deviceLine = & $adb devices -l |
    Where-Object { $_ -match "^$([regex]::Escape($DeviceId))\s+device\b" }
if (!$deviceLine) {
    throw "Android device is missing or unauthorized: $DeviceId"
}
$abi = (& $adb -s $DeviceId shell getprop ro.product.cpu.abi).Trim()
if ($abi -ne $ExpectedAbi) {
    throw "Device ABI mismatch: expected $ExpectedAbi, actual $abi"
}

Push-Location $appRoot
try {
    if ($Release) {
        & $flutter drive `
            --driver=test_driver/integration_test.dart `
            --target=integration_test/android_sdcc_smoke_test.dart `
            -d $DeviceId --release `
            --dart-define="PIEBLOCK_STABILITY_ITERATIONS=$StabilityIterations"
        if ($LASTEXITCODE -ne 0) { throw 'Android SDCC smoke/fault/stability test failed' }

        & $flutter drive `
            --driver=test_driver/integration_test.dart `
            --target=integration_test/android_sdcc_full_build_test.dart `
            -d $DeviceId --release `
            --dart-define="PIEBLOCK_GOLDEN_KIND=all" `
            --dart-define="PIEBLOCK_GOLDEN_REPETITIONS=$FullBuildRepetitions"
        if ($LASTEXITCODE -ne 0) { throw 'Android SDCC full golden matrix failed' }
    } else {
        & $flutter test integration_test/android_sdcc_smoke_test.dart `
            -d $DeviceId `
            --dart-define="PIEBLOCK_STABILITY_ITERATIONS=$StabilityIterations"
        if ($LASTEXITCODE -ne 0) { throw 'Android SDCC smoke/fault/stability test failed' }

        & $flutter test integration_test/android_sdcc_full_build_test.dart `
            -d $DeviceId `
            --dart-define="PIEBLOCK_GOLDEN_KIND=all" `
            --dart-define="PIEBLOCK_GOLDEN_REPETITIONS=$FullBuildRepetitions"
        if ($LASTEXITCODE -ne 0) { throw 'Android SDCC full golden matrix failed' }
    }
} finally {
    Pop-Location
}

Write-Output "Android SDCC acceptance passed: $DeviceId ($ExpectedAbi)"
