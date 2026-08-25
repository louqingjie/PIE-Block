param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath
)

$ErrorActionPreference = "Stop"
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackage)
try {
    $names = @($archive.Entries | ForEach-Object FullName)
    $prefix = if ([IO.Path]::GetExtension($resolvedPackage) -eq '.aab') {
        'base/'
    } else {
        ''
    }
    $forbidden = @($names | Where-Object {
        $_ -match '(^|/)(sdcc|sdcpp|sdas251|sdld)(\.exe)?$' -or
        $_ -match '\.(exe|dll)$'
    })
    if ($forbidden.Count -ne 0) {
        throw "Android 包含禁止发布的编译器可执行文件：$($forbidden -join ', ')"
    }

    $unsupportedAbi = @($names | Where-Object {
        $_ -match "^$([regex]::Escape($prefix))lib/(armeabi-v7a|x86|mips)/"
    })
    if ($unsupportedAbi.Count -ne 0) {
        throw "Android 包含未支持 ABI 的原生库：$($unsupportedAbi -join ', ')"
    }

    foreach ($abi in @('arm64-v8a', 'x86_64')) {
        $library = "${prefix}lib/$abi/libpieblock_sdcc_native.so"
        if ($library -notin $names) {
            throw "Android 包缺少 $library"
        }
    }

    $manifestEntry = $archive.GetEntry(
        "${prefix}assets/pieblock_sdcc/bundle_manifest.json"
    )
    if ($null -eq $manifestEntry) {
        throw "Android 包缺少 SDCC 资源清单"
    }
    $reader = [System.IO.StreamReader]::new(
        $manifestEntry.Open(),
        [System.Text.Encoding]::UTF8
    )
    try {
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
    } finally {
        $reader.Dispose()
    }
    if ($manifest.format_version -ne 1) {
        throw "不支持的 SDCC 资源清单版本：$($manifest.format_version)"
    }
    $resourceNames = @($manifest.files.PSObject.Properties.Name)
    foreach ($relative in $resourceNames) {
        if ($null -eq $archive.GetEntry("${prefix}assets/pieblock_sdcc/$relative")) {
            throw "Android 包缺少清单资源：$relative"
        }
    }

    Write-Output "Android 包校验通过"
    Write-Output "文件：$resolvedPackage"
    Write-Output "SDCC 资源：$($resourceNames.Count) 个"
    Write-Output "资源指纹：$($manifest.fingerprint)"
} finally {
    $archive.Dispose()
}
