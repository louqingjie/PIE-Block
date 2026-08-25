param(
    [Parameter(Mandatory = $true)]
    [string]$BuildRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$NdkRoot = 'C:\android\ndk\28.2.13676358'
)

$ErrorActionPreference = 'Stop'
$resolvedBuild = (Resolve-Path -LiteralPath $BuildRoot).Path
$resolvedNdk = (Resolve-Path -LiteralPath $NdkRoot).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) {
    throw "输出目录已存在，为避免覆盖请指定空目录：$output"
}
New-Item -ItemType Directory -Path $output | Out-Null

$toolDirectory = Join-Path $resolvedNdk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$nm = Join-Path $toolDirectory 'llvm-nm.exe'
$objcopy = Join-Path $toolDirectory 'llvm-objcopy.exe'
$clang = Join-Path $toolDirectory 'clang++.exe'
$clangC = Join-Path $toolDirectory 'clang.exe'
$target = switch ($Abi) {
    'arm64-v8a' { 'aarch64-linux-android24' }
    'x86_64' { 'x86_64-linux-android24' }
}
foreach ($tool in @($nm, $objcopy, $clang, $clangC)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "缺少 NDK 工具：$tool"
    }
}

function Copy-NamespaceGroup {
    param(
        [string]$Name,
        [string[]]$Files,
        [string]$MainObject,
        [string]$EntryPoint
    )
    $directory = Join-Path $output $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $copies = @()
    for ($index = 0; $index -lt $Files.Count; $index++) {
        $source = $Files[$index]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "缺少阶段输入：$source"
        }
        $destination = Join-Path $directory (
            '{0:D2}_{1}' -f $index, [IO.Path]::GetFileName($source)
        )
        Copy-Item -LiteralPath $source -Destination $destination
        $copies += $destination
    }
    $main = $copies | Where-Object {
        [IO.Path]::GetFileName($_) -like "*_$MainObject"
    }
    if (@($main).Count -ne 1) {
        throw "阶段 $Name 无法唯一定位入口对象 $MainObject"
    }
    & $objcopy --redefine-sym "main=$EntryPoint" $main
    if ($LASTEXITCODE -ne 0) { throw "重命名 $Name 入口失败" }

    $symbols = @()
    foreach ($file in $copies) {
        $symbols += & $nm -g --defined-only $file | ForEach-Object {
            if ($_ -match '^\s*(?:[0-9A-Fa-f]+|)\s*[A-Za-z]\s+(\S+)$') {
                $matches[1]
            }
        }
    }
    $symbols = @($symbols | Sort-Object -Unique | Where-Object {
        $_ -ne $EntryPoint -and
        $_ -notmatch '^(__dso_handle|_DYNAMIC|_GLOBAL_OFFSET_TABLE_)$'
    })
    $map = Join-Path $directory 'rename.map'
    $symbols | ForEach-Object { "$_ pb_${Name}_$_" } |
        Set-Content -LiteralPath $map -Encoding ascii
    foreach ($file in $copies) {
        & $objcopy "--redefine-syms=$map" $file
        if ($LASTEXITCODE -ne 0) { throw "隔离 $Name 符号失败：$file" }
        & $objcopy `
            --redefine-sym "exit=pb_${Name}_exit" `
            --redefine-sym "abort=pb_${Name}_abort" `
            $file
        if ($LASTEXITCODE -ne 0) { throw "接管 $Name 退出路径失败：$file" }
        if ($Name -eq 'sdcc') {
            & $objcopy `
                --redefine-sym 'system=pb_sdcc_system' `
                --redefine-sym 'popen=pb_sdcc_popen' `
                --redefine-sym 'pclose=pb_sdcc_pclose' `
                $file
            if ($LASTEXITCODE -ne 0) { throw "禁用 SDCC 子进程调用失败：$file" }
        }
    }
    Write-Host "$Name：已隔离 $($symbols.Count) 个全局符号"
    return ,$copies
}

$sdccDirectory = Join-Path $resolvedBuild 'src'
$sdccFiles = @(
    Get-ChildItem -LiteralPath $sdccDirectory -File -Filter '*.o' |
        Sort-Object Name |
        ForEach-Object FullName
) + @(Join-Path $sdccDirectory 'mcs251\port.a')
$assemblerFiles = @(
    Get-ChildItem -LiteralPath (
        Join-Path $resolvedBuild 'sdas\as251\obj'
    ) -File -Filter '*.o' | Sort-Object Name | ForEach-Object FullName
)
$linkerFiles = @(
    Get-ChildItem -LiteralPath (
        Join-Path $resolvedBuild 'sdas\linksrc\obj'
    ) -File -Filter '*.o' | Sort-Object Name | ForEach-Object FullName
)

$gcc = Join-Path $resolvedBuild 'support\cpp\gcc'
$cppDirect = @(
    'c-family\c-common.o',
    'c\c-lang.o',
    'c\c-errors.o',
    'c\c-convert.o',
    'c\gimple-parser.o',
    'c\c-objc-common.o',
    'c-family\c-cppbuiltin.o',
    'c-family\c-dump.o',
    'c-family\c-indentation.o',
    'c-family\c-opts.o',
    'c-family\c-ppoutput.o',
    'c-family\c-pragma.o',
    'c-family\c-lex.o',
    'cc1_dummies.o',
    'main.o'
) | ForEach-Object { Join-Path $gcc $_ }
$cppArchives = @(
    (Join-Path $gcc 'libbackend.a'),
    (Join-Path $gcc 'libcommon-target.a'),
    (Join-Path $gcc 'libcommon.a'),
    (Join-Path $resolvedBuild 'support\cpp\libcpp\libcpp.a'),
    (Join-Path $resolvedBuild 'support\cpp\libbacktrace\.libs\libbacktrace.a'),
    (Join-Path $resolvedBuild 'support\sdbinutils\libiberty\libiberty.a')
)

$cpp = Copy-NamespaceGroup cpp ($cppDirect + $cppArchives) 'main.o' 'pb_cpp_main'
$sdcc = Copy-NamespaceGroup sdcc $sdccFiles 'SDCCmain.o' 'pb_sdcc_main'
$assembler = Copy-NamespaceGroup as $assemblerFiles 'asmain.o' 'pb_sdas251_main'
$linker = Copy-NamespaceGroup ld $linkerFiles 'lkmain.o' 'pb_sdld_main'

$runtimeSource = Join-Path $PSScriptRoot (
    '..\packages\pieblock_sdcc_native\src\pieblock_sdcc_stage_runtime.c'
)
$runtimeObject = Join-Path $output 'pieblock_sdcc_stage_runtime.o'
& $clangC `
    "--target=$target" `
    '-std=gnu17' `
    '-fPIC' `
    '-c' `
    $runtimeSource `
    '-o' `
    $runtimeObject
if ($LASTEXITCODE -ne 0) { throw '编译受控阶段运行时失败' }

# GCC/libcpp archives are repeated to preserve the upstream circular-resolution
# order. The first 15 entries are direct cc1 objects; the final six are archives.
$cppLinkOrder = @($cpp[0..14]) + @(
    $cpp[15], $cpp[16], $cpp[17], $cpp[18], $cpp[17], $cpp[18],
    $cpp[19], $cpp[20], '-lz'
)
$library = Join-Path $output 'libpieblock_sdcc_probe.so'
$arguments = @(
    "--target=$target",
    '-shared',
    '-Wl,-soname,libpieblock_sdcc_probe.so',
    '-o',
    $library
) + $cppLinkOrder + $sdcc + $assembler + $linker + @($runtimeObject, '-lm')
& $clang @arguments
if ($LASTEXITCODE -ne 0) { throw '合并四阶段共享库失败' }

$stageObject = Join-Path $output 'pieblock_sdcc_stages.o'
$relocatableArguments = @(
    "--target=$target",
    '-nostdlib',
    '-no-pie',
    '-Wl,-r',
    '-o',
    $stageObject
) + @($cppLinkOrder | Where-Object { $_ -ne '-lz' }) +
    $sdcc + $assembler + $linker
& $clang @relocatableArguments
if ($LASTEXITCODE -ne 0) { throw '生成四阶段可重定位对象失败' }

$exports = @(& $nm -D $library | Where-Object {
    $_ -match 'pb_(cpp|sdcc|sdas251|sdld)_main$'
})
if ($exports.Count -ne 4) {
    throw "共享库入口不完整：预期 4 个，实际 $($exports.Count) 个"
}
Write-Output "四阶段共享库探针生成成功：$library"
Write-Output "大小：$((Get-Item -LiteralPath $library).Length) 字节"
Write-Output "可重定位阶段对象：$stageObject"
Write-Output "大小：$((Get-Item -LiteralPath $stageObject).Length) 字节"
$exports
