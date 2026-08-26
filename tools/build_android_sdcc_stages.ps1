param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [ValidateSet('arm64-v8a', 'x86_64', 'all')]
    [string]$Abi = 'all',

    [string]$NdkRoot = 'C:\android\ndk\28.2.13676358',
    [string]$MsysRoot = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot 'sdcc-c251'
$expectedCommit = '912a589d4080c9cd5c5c1faf871c62dd5023580d'
$actualCommit = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "SDCC 子模块提交不匹配：需要 $expectedCommit，实际 $actualCommit"
}

$resolvedNdk = (Resolve-Path -LiteralPath $NdkRoot).Path
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
    throw "缺少 MSYS2 Bash：$bash"
}
$boostRoot = Join-Path $MsysRoot 'ucrt64\include'
$boostVersion = Join-Path $boostRoot 'boost\version.hpp'
if (-not (Test-Path -LiteralPath $boostVersion -PathType Leaf) -or
    -not (Select-String -LiteralPath $boostVersion -Quiet -Pattern '#define BOOST_VERSION 108900')) {
    throw 'Android SDCC 阶段构建需要固定的 Boost 1.89.0 头文件'
}

function Convert-ToMsysPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "无法转换为 MSYS2 路径：$full"
    }
    return '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash($stream)
        ) -replace '-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Invoke-Msys([string]$Command) {
    & $bash -lc "export PATH=/ucrt64/bin:`$PATH; $Command"
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 命令失败，退出码 $LASTEXITCODE"
    }
}

function Build-StageObject([string]$TargetAbi) {
    $target = if ($TargetAbi -eq 'arm64-v8a') {
        'aarch64-linux-android24'
    } else {
        'x86_64-linux-android24'
    }
    $targetHost = if ($TargetAbi -eq 'arm64-v8a') {
        'aarch64-linux-android'
    } else {
        'x86_64-linux-android'
    }
    $destination = [IO.Path]::GetFullPath((Join-Path $OutputRoot $TargetAbi))
    $manifestPath = Join-Path $destination 'stage_manifest.json'
    $stagePath = Join-Path $destination 'pieblock_sdcc_stages.o'
    $cacheKey = "$expectedCommit|$TargetAbi|android24|ndk-28.2.13676358|ffi-5|stage-layout-5"
    if ((Test-Path -LiteralPath $manifestPath) -and (Test-Path -LiteralPath $stagePath)) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $actualHash = Get-Sha256 $stagePath
        if ($manifest.cache_key -eq $cacheKey -and $manifest.sha256 -eq $actualHash) {
            Write-Output "复用 $TargetAbi SDCC 阶段对象：$stagePath"
            return
        }
    }

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'pieblock-sdcc-stage-' + $TargetAbi + '-' + [Guid]::NewGuid().ToString('N')
    )
    $sourceCopy = Join-Path $temporaryRoot 'source'
    $buildRoot = Join-Path $temporaryRoot 'build'
    $linkRoot = Join-Path $temporaryRoot 'linked'
    New-Item -ItemType Directory -Path $sourceCopy, $buildRoot | Out-Null
    $completed = $false
    try {
        $archive = Join-Path $temporaryRoot 'sdcc-source.tar'
        & git -C $sourceRoot archive --format=tar --output=$archive HEAD
        if ($LASTEXITCODE -ne 0) { throw '无法导出固定 SDCC 源码' }
        & tar -xf $archive -C $sourceCopy
        if ($LASTEXITCODE -ne 0) { throw '无法展开固定 SDCC 源码' }
        # The repository carries a CRLF-terminated version marker. Autoconf
        # embeds it inside a C string, so normalize the build copy first.
        $versionFile = Join-Path $sourceCopy '.version'
        $version = (Get-Content -LiteralPath $versionFile -First 1).Trim()
        [IO.File]::WriteAllText(
            $versionFile,
            $version,
            [Text.UTF8Encoding]::new($false)
        )
        # GCC's cc1 entry only runs its documented repeat-call cleanup in
        # checking builds. The Android embedded host invokes that entry once
        # per translation unit, so make the existing cleanup unconditional in
        # this pinned build copy.
        $cppMain = Join-Path $sourceCopy 'support\cpp\gcc\main.cc'
        $cppMainText = [IO.File]::ReadAllText($cppMain)
        $finalizePattern = '(?m)^  if \(flag_checking && !seen_error \(\)\)\r?$\n^    toplev\.finalize \(\);\r?$'
        if (-not [Text.RegularExpressions.Regex]::IsMatch(
            $cppMainText,
            $finalizePattern
        )) {
            throw '无法应用 sdcpp 可重复调用清理补丁'
        }
        $cppMainText = [Text.RegularExpressions.Regex]::Replace(
            $cppMainText,
            $finalizePattern,
            "  /* PIE-Block embedded host: reset cc1 after every unit. */`n  toplev.finalize ();"
        )
        [IO.File]::WriteAllText(
            $cppMain,
            $cppMainText,
            [Text.UTF8Encoding]::new($false)
        )

        # The stripped sdcpp host never initializes GCC's dump subsystem.
        # Its placeholder destructor aborts because one-shot sdcpp never
        # destroys the context. The embedded host does so between translation
        # units, therefore make that otherwise empty placeholder a no-op in
        # the isolated source copy.
        $cppDummies = Join-Path $sourceCopy 'support\cpp\gcc\cc1_dummies.cc'
        $cppDummiesText = [IO.File]::ReadAllText($cppDummies)
        $dumpDestructorPattern = '(?m)^dump_manager::~dump_manager\(\)\r?$\n^\{ SDCPP_DUMMY_FCT\(\);\r?$\n^\}\r?$'
        if (-not [Text.RegularExpressions.Regex]::IsMatch(
            $cppDummiesText,
            $dumpDestructorPattern
        )) {
            throw '无法应用 sdcpp dump_manager 析构补丁'
        }
        $cppDummiesText = [Text.RegularExpressions.Regex]::Replace(
            $cppDummiesText,
            $dumpDestructorPattern,
            "dump_manager::~dump_manager()`n{`n  /* No dump state exists in the stripped sdcpp host. */`n}"
        )
        [IO.File]::WriteAllText(
            $cppDummies,
            $cppDummiesText,
            [Text.UTF8Encoding]::new($false)
        )

        New-Item -ItemType Directory -Force -Path (Join-Path $buildRoot 'include') | Out-Null
        Copy-Item -LiteralPath (Join-Path $boostRoot 'boost') `
            -Destination (Join-Path $buildRoot 'include\boost') -Recurse

        $toolRoot = Join-Path $resolvedNdk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
        $compiler = Convert-ToMsysPath (Join-Path $toolRoot "$target-clang.cmd")
        $compilerCxx = Convert-ToMsysPath (Join-Path $toolRoot "$target-clang++.cmd")
        $ar = Convert-ToMsysPath (Join-Path $toolRoot 'llvm-ar.exe')
        $ranlib = Convert-ToMsysPath (Join-Path $toolRoot 'llvm-ranlib.exe')
        $strip = Convert-ToMsysPath (Join-Path $toolRoot 'llvm-strip.exe')
        $configure = Convert-ToMsysPath (Join-Path $sourceCopy 'configure')
        $build = Convert-ToMsysPath $buildRoot
        $disabledPorts = @(
            'mcs51', 'z80', 'z180', 'r2k', 'r2ka', 'r3ka', 'r4k', 'r5k',
            'r6k', 'sm83', 'tlcs90', 'ez80', 'z80n', 'r800', 'ds390',
            'ds400', 'pic14', 'pic16', 'hc08', 's08', 'stm8', 'pdk13',
            'pdk14', 'pdk15', 'mos6502', 'mos65c02', 'f8', 'f8l'
        ) | ForEach-Object { "--disable-$_-port" }
        $configureArgs = @(
            "'$configure'",
            "--host=$targetHost",
            '--build=x86_64-pc-msys',
            # The bundled GCC preprocessor sources intentionally retain only
            # the x86 target description. The produced cc1 still runs on the
            # Android host selected above; this target only supplies the
            # preprocessor's builtin machine description.
            '--target=x86_64-pc-linux-gnu',
            "CC='$compiler'",
            "CXX='$compilerCxx'",
            "AR='$ar'",
            "RANLIB='$ranlib'",
            "STRIP='$strip'",
            "CFLAGS='-std=gnu17 -fPIC'",
            "CXXFLAGS='-std=gnu++17 -fPIC'",
            "CPPFLAGS='-I$build/include'",
            '--enable-mcs251-port'
        ) + $disabledPorts + @(
            '--disable-ucsim', '--disable-device-lib', '--disable-packihx',
            '--disable-sdcdb', '--disable-sdbinutils', '--disable-non-free'
        )
        Invoke-Msys "cd '$build' && $($configureArgs -join ' ')"
        $libibertySource = Convert-ToMsysPath (
            Join-Path $sourceCopy 'support\sdbinutils\libiberty\configure'
        )
        $libibertyBuild = "$build/support/sdbinutils/libiberty"
        Invoke-Msys (
            "mkdir -p '$libibertyBuild' && cd '$libibertyBuild' && " +
            "'$libibertySource' --host=$targetHost --build=x86_64-pc-msys " +
            "CC='$compiler' AR='$ar' RANLIB='$ranlib' " +
            "CFLAGS='-std=gnu17 -fPIC' CPPFLAGS='-I$build/include' " +
            '--disable-shared --enable-static'
        )
        Invoke-Msys "cd '$libibertyBuild' && make -j4 libiberty.a"
        Invoke-Msys "cd '$build' && make -j4"

        & (Join-Path $PSScriptRoot 'link_android_sdcc_probe.ps1') `
            -BuildRoot $buildRoot `
            -Abi $TargetAbi `
            -OutputDirectory $linkRoot `
            -NdkRoot $resolvedNdk
        if ($LASTEXITCODE -ne 0) { throw '无法生成命名空间隔离的阶段对象' }

        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -LiteralPath (Join-Path $linkRoot 'pieblock_sdcc_stages.o') `
            -Destination $stagePath -Force
        $hash = Get-Sha256 $stagePath
        [ordered]@{
            format_version = 1
            cache_key = $cacheKey
            sdcc_commit = $expectedCommit
            abi = $TargetAbi
            api_level = 24
            ndk = '28.2.13676358'
            sha256 = $hash
        } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-Output "生成 $TargetAbi SDCC 阶段对象：$stagePath"
        $completed = $true
    } finally {
        if ($completed -and (Test-Path -LiteralPath $temporaryRoot)) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        } elseif (Test-Path -LiteralPath $temporaryRoot) {
            Write-Warning "构建失败，诊断目录保留在：$temporaryRoot"
        }
    }
}

$targets = if ($Abi -eq 'all') { @('arm64-v8a', 'x86_64') } else { @($Abi) }
foreach ($targetAbi in $targets) {
    Build-StageObject $targetAbi
}
