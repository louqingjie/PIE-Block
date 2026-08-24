[CmdletBinding()]
param(
    [ValidateSet('0000.培训模板', '0001.JDY08设置密码', 'FRICTION_CALIBRATION', 'LCD_SPI_SMOKE', 'ROBOMASTER_ENGINEER', 'ROBOMASTER_INFANTRY', 'TEST')]
    [string]$Project = 'TEST',
    [switch]$All,
    [switch]$SmokeTest,
    [string]$Sdcc = $env:SDCC,
    [string]$LibDir = $env:SDCC_LIB_DIR,
    [string]$StdInclude = $env:SDCC_INCLUDE_DIR,
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'build')
)

$ErrorActionPreference = 'Stop'

$projectNames = @(
    '0000.培训模板',
    '0001.JDY08设置密码',
    'FRICTION_CALIBRATION',
    'LCD_SPI_SMOKE',
    'ROBOMASTER_ENGINEER',
    'ROBOMASTER_INFANTRY',
    'TEST'
)

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

$sdcc = Resolve-Executable $Sdcc
$sdccBin = Split-Path -Parent $sdcc
$env:Path = $sdccBin + ';' + $env:Path
$siblingBin = Join-Path $sdccBin '..\bin'
if (Test-Path -LiteralPath $siblingBin -PathType Container) {
    $env:Path = (Resolve-Path -LiteralPath $siblingBin).Path + ';' + $env:Path
}

if ([string]::IsNullOrWhiteSpace($StdInclude)) {
    $StdInclude = Join-Path $PSScriptRoot '..\sdcc-c251\device\include'
}
$StdInclude = Resolve-Directory $StdInclude 'SDCC 标准头文件目录'

if ([string]::IsNullOrWhiteSpace($LibDir)) {
    $LibDir = Join-Path $PSScriptRoot '..\sdcc-c251\device\lib\build\mcs251-large-stack-auto'
}
$LibDir = Resolve-Directory $LibDir 'SDCC MCS-251 large-stack-auto 运行库目录'

$includePaths = @(
    $StdInclude,
    (Join-Path $StdInclude 'mcs51'),
    (Join-Path $PSScriptRoot 'include'),
    (Join-Path $PSScriptRoot 'startup'),
    (Join-Path $PSScriptRoot 'libraries\drivers\inc'),
    (Join-Path $PSScriptRoot 'libraries\boards\inc')
)

$sourceCommon = @(
    'startup\common.c',
    'startup\stc32g12k128_startup.c'
)
$sourceDrivers = @(
    'libraries\drivers\src\CNU_PIE_GPIO.c',
    'libraries\drivers\src\CNU_PIE_TIMER.c',
    'libraries\drivers\src\CNU_PIE_EXTI.c',
    'libraries\drivers\src\CNU_PIE_ADC.c',
    'libraries\drivers\src\CNU_PIE_I2C.c',
    'libraries\drivers\src\CNU_PIE_SPI.c',
    'libraries\drivers\src\CNU_PIE_PWM.c',
    'libraries\drivers\src\CNU_PIE_WDog.c',
    'libraries\drivers\src\CNU_PIE_UART.c',
    'libraries\drivers\src\CNU_PIE_FIFO.c'
)
$sourceBoards = @(
    'libraries\boards\src\BMI088driver.c',
    'libraries\boards\src\BMI088Middleware.c',
    'libraries\boards\src\Encoder.c',
    'libraries\boards\src\OLED.c',
    'libraries\boards\src\LCD.c',
    'libraries\boards\src\Font.c'
)
$sourceBoardsWithRadio = $sourceBoards + @(
    'libraries\boards\src\remote_control.c',
    'libraries\boards\src\nrf24l01.c'
)

$sourceMap = @{
    '0000.培训模板' = $sourceCommon + @('projects\0000.培训模板\src\isr.c', 'projects\0000.培训模板\src\main.c') + $sourceBoardsWithRadio + $sourceDrivers
    '0001.JDY08设置密码' = $sourceCommon + @('projects\0001.JDY08设置密码\src\isr.c', 'projects\0001.JDY08设置密码\src\main.c') + $sourceBoardsWithRadio + $sourceDrivers
    'FRICTION_CALIBRATION' = $sourceCommon + @('projects\FRICTION_CALIBRATION\src\isr.c', 'projects\FRICTION_CALIBRATION\src\main.c') + $sourceBoards + $sourceDrivers
    'LCD_SPI_SMOKE' = $sourceCommon + @('projects\LCD_SPI_SMOKE\src\isr.c', 'projects\LCD_SPI_SMOKE\src\main.c', 'libraries\boards\src\LCD.c', 'libraries\boards\src\Font.c', 'libraries\drivers\src\CNU_PIE_GPIO.c')
    'ROBOMASTER_ENGINEER' = $sourceCommon + @('projects\ROBOMASTER_ENGINEER\src\isr.c', 'projects\ROBOMASTER_ENGINEER\src\main.c') + $sourceBoardsWithRadio + $sourceDrivers
    'ROBOMASTER_INFANTRY' = $sourceCommon + @('projects\ROBOMASTER_INFANTRY\src\isr.c', 'projects\ROBOMASTER_INFANTRY\src\main.c') + $sourceBoardsWithRadio + $sourceDrivers
    'TEST' = $sourceCommon + @('projects\TEST\src\isr.c', 'projects\TEST\src\main.c') + $sourceBoardsWithRadio + $sourceDrivers
}

$includeArgs = @()
foreach ($path in $includePaths) {
    $includeArgs += '-I' + (Resolve-Directory $path '工程头文件目录')
}

$libraryNames = @(
    'mcs251.lib',
    'libsdcc.lib',
    'liblong.lib',
    'libint.lib',
    'libfloat.lib',
    'liblonglong.lib'
)
foreach ($library in $libraryNames) {
    if (!(Test-Path -LiteralPath (Join-Path $LibDir $library) -PathType Leaf)) {
        throw "SDCC 运行库缺失: $(Join-Path $LibDir $library)"
    }
}

function Invoke-Sdcc([string[]]$Arguments) {
    & $sdcc @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "SDCC 执行失败，退出码 $LASTEXITCODE"
    }
}

function Invoke-ProjectBuild([string]$Name) {
    $projectRoot = Join-Path $PSScriptRoot ('projects\' + $Name)
    $projectInclude = Resolve-Directory (Join-Path $projectRoot 'inc') '工程专用头文件目录'
    $projectIncludeArgs = @('-I' + $projectInclude)
    $output = Join-Path $OutputRoot $Name
    New-Item -ItemType Directory -Force -Path $output | Out-Null

    $libraryRelativeSources = if ($Name -eq 'FRICTION_CALIBRATION') {
        $sourceBoards + $sourceDrivers
    } elseif ($Name -eq 'LCD_SPI_SMOKE') {
        @('libraries\boards\src\LCD.c', 'libraries\boards\src\Font.c', 'libraries\drivers\src\CNU_PIE_GPIO.c')
    } else {
        $sourceBoardsWithRadio + $sourceDrivers
    }
    $directObjects = @()
    $libraryObjects = @()
    foreach ($relativeSource in $sourceMap[$Name]) {
        $source = Join-Path $PSScriptRoot $relativeSource
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "工程源文件缺失: $source"
        }
        $objectName = [IO.Path]::GetFileNameWithoutExtension($source) + '.rel'
        $object = Join-Path $output $objectName
        $compileArgs = @(
            '-mmcs251',
            '--model-large',
            '--stack-auto',
            '--opt-code-size',
            '--constseg', 'CSEG',
            '--no-xinit-opt',
            '-c'
        ) + $includeArgs + $projectIncludeArgs + @('-o', $object, $source)
        Invoke-Sdcc $compileArgs
        if ($libraryRelativeSources -contains $relativeSource) {
            $libraryObjects += $object
        } else {
            $directObjects += $object
        }
    }

    $hex = Join-Path $output ($Name + '.hex')
    $sharedLibrary = Join-Path $output 'stc32g_shared.lib'
    $libraryEntries = $libraryObjects | ForEach-Object {
        [IO.Path]::GetFileNameWithoutExtension($_)
    }
    Set-Content -LiteralPath $sharedLibrary -Value $libraryEntries -Encoding ascii
    $linkArgs = @(
        '-mmcs251',
        '--model-large',
        '--stack-auto',
        '--constseg', 'CSEG',
        '--nostdlib',
        '--no-xinit-opt',
        '--iram-size', '0x1000',
        '--xram-loc', '0x010000',
        '--xram-size', '0x2000',
        '--code-loc', '0xff0000',
        '-Wl-b GSINIT0=0xfe0000',
        ('-L' + $output),
        ('-L' + $LibDir)
    ) + $includeArgs + $projectIncludeArgs + $directObjects + @('stc32g_shared.lib') + $libraryNames + @('-o', $hex)
    Invoke-Sdcc $linkArgs

    $map = [IO.Path]::ChangeExtension($hex, '.map')
    if (!(Test-Path -LiteralPath $hex -PathType Leaf) -or !(Test-Path -LiteralPath $map -PathType Leaf)) {
        throw "工程没有生成完整 HEX/MAP: $Name"
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $python) {
        throw '找不到 python，无法执行布局验证。'
    }
    & $python.Source (Join-Path $PSScriptRoot 'tools\check_layout.py') $hex --map $map
    if ($LASTEXITCODE -ne 0) {
        throw "HEX/MAP 布局验证失败: $Name"
    }
    Write-Host ("[PASS] " + $Name + ' -> ' + $hex)
}

if ($SmokeTest) {
    $smokeOutput = Join-Path $OutputRoot 'smoke'
    New-Item -ItemType Directory -Force -Path $smokeOutput | Out-Null
    $smokeAsm = Join-Path $smokeOutput 'sdcc_compat_smoke.asm'
    $smokeArgs = @('-mmcs251', '--model-large', '--stack-auto', '-S') + $includeArgs + @('-o', $smokeAsm, (Join-Path $PSScriptRoot 'tests\sdcc_compat_smoke.c'))
    Invoke-Sdcc $smokeArgs
    Write-Host ('[PASS] SDCC compatibility smoke -> ' + $smokeAsm)
}

$targets = if ($All) { $projectNames } else { @($Project) }
foreach ($target in $targets) {
    Invoke-ProjectBuild $target
}
