[CmdletBinding()]
param(
    [ValidateSet('gpio', 'uart', 'spi', 'qemu')]
    [string]$Test = 'gpio',
    [switch]$All,
    [string]$Sdcc = $env:SDCC,
    [string]$LibDir = $env:SDCC_LIB_DIR,
    [string]$StdInclude = $env:SDCC_INCLUDE_DIR,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\build\minimal')
)

$ErrorActionPreference = 'Stop'

function Resolve-Executable([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw '未指定 SDCC。请使用 -Sdcc 或设置 SDCC 环境变量。'
    }
    if (Test-Path -LiteralPath $Name -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Name).Path
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "找不到 SDCC: $Name"
    }
    return $command.Source
}

function Resolve-Directory([string]$Path, [string]$Description) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description 不存在: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-Sdcc([string[]]$Arguments) {
    Write-Verbose ('sdcc ' + ($Arguments -join ' '))
    & $sdcc @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "SDCC 执行失败，退出码 $LASTEXITCODE"
    }
}

$sdcc = Resolve-Executable $Sdcc
$sdccBin = Split-Path -Parent $sdcc
$env:Path = $sdccBin + ';' + $env:Path
if ([string]::IsNullOrWhiteSpace($StdInclude)) {
    $StdInclude = Join-Path $PSScriptRoot '..\..\sdcc-c251\device\include'
}
if ([string]::IsNullOrWhiteSpace($LibDir)) {
    $LibDir = Join-Path $PSScriptRoot '..\..\sdcc-c251\device\lib\build\mcs251-large-stack-auto'
}
$StdInclude = Resolve-Directory $StdInclude 'SDCC 标准头文件目录'
$LibDir = Resolve-Directory $LibDir 'SDCC MCS-251 运行库目录'
$projectInclude = Resolve-Directory (Join-Path $PSScriptRoot '..\include') 'STC32G SDCC 头文件目录'
$includeArgs = @('-I', $StdInclude, '-I', $projectInclude)
$firmwareRoot = Join-Path $PSScriptRoot 'firmware'
$layoutChecker = Join-Path $PSScriptRoot '..\tools\check_layout.py'
$targets = if ($All) { @('gpio', 'uart', 'spi', 'qemu') } else { @($Test) }

foreach ($target in $targets) {
    $output = Join-Path $OutputRoot $target
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $objects = @()
    foreach ($sourceName in @('default_isr.c', ($target + '_smoke.c'))) {
        $source = Join-Path $firmwareRoot $sourceName
        $object = Join-Path $output ([IO.Path]::GetFileNameWithoutExtension($sourceName) + '.rel')
        $compileArgs = @('-mmcs251', '--model-large', '--stack-auto', '--opt-code-size', '--constseg', 'CSEG', '--no-xinit-opt', '-c') + $includeArgs + @('-o', $object, $source)
        Invoke-Sdcc $compileArgs
        $objects += $object
    }
    $hex = Join-Path $output ($target + '_smoke.hex')
    $linkArgs = @(
        '-mmcs251', '--model-large', '--stack-auto', '--constseg', 'CSEG', '--nostdlib', '--no-xinit-opt',
        '--iram-size', '0x1000', '--xram-loc', '0x010000', '--xram-size', '0x2000', '--code-loc', '0xff0000',
        '-Wl-b GSINIT0=0xfe0000', ('-L' + $LibDir)
    ) + $includeArgs + $objects + @('mcs251.lib', 'libsdcc.lib', 'liblong.lib', 'libint.lib', 'libfloat.lib', 'liblonglong.lib', '-o', $hex)
    Invoke-Sdcc $linkArgs
    & python (Join-Path $PSScriptRoot '..\tools\check_layout.py') $hex --map ([IO.Path]::ChangeExtension($hex, '.map'))
    if ($LASTEXITCODE -ne 0) {
        throw "最小固件布局验证失败: $target"
    }
    Write-Host "[PASS] minimal $target -> $hex"
}
