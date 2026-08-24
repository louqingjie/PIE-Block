[CmdletBinding(DefaultParameterSetName = 'Config')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Config')]
    [string]$Config,
    [Parameter(Mandatory = $true, ParameterSetName = 'Midi')]
    [string]$Midi,
    [ValidateSet('BUZZER_MUSIC_SMOKE', 'BUZZER_MUSIC_SONG_SMOKE', 'BUZZER_MUSIC_GENERATED')]
    [string]$Project = 'BUZZER_MUSIC_GENERATED',
    [string]$Godot = $env:GODOT,
    [string]$Sdcc = $env:SDCC,
    [string]$LibDir = $env:SDCC_LIB_DIR,
    [string]$StdInclude = $env:SDCC_INCLUDE_DIR,
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'build')
)

$ErrorActionPreference = 'Stop'

function Resolve-Tool([string]$Name, [string]$Description) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "未指定 $Description。请使用参数或设置对应环境变量。"
    }
    if (Test-Path -LiteralPath $Name -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Name).Path
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "找不到 ${Description}: $Name"
    }
    return $command.Source
}

function Resolve-InputFile([string]$Path, [string]$Description) {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description 不存在: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$godotExe = Resolve-Tool $Godot 'Godot'
$cli = Join-Path $repoRoot 'scripts\cli_codegen.gd'
$projectRoot = Join-Path $PSScriptRoot ('projects\' + $Project)
$mainC = Join-Path $projectRoot 'src\main.c'
if (!(Test-Path -LiteralPath $mainC -PathType Leaf)) {
    throw "音乐工程缺少 main.c: $mainC"
}

$testRoot = Join-Path $env:TEMP 'pie-block-godot-test'
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$env:APPDATA = Join-Path $testRoot 'Roaming'
$env:LOCALAPPDATA = Join-Path $testRoot 'Local'

$configPath = ''
if ($PSCmdlet.ParameterSetName -eq 'Midi') {
    $midiPath = Resolve-InputFile $Midi 'MIDI 文件'
    $generatedConfigDir = Join-Path $OutputRoot $Project
    New-Item -ItemType Directory -Force -Path $generatedConfigDir | Out-Null
    $configPath = Join-Path $generatedConfigDir 'generated_music.json'
    & $godotExe --headless --no-header --path $repoRoot --script $cli -- `
        music-config --midi $midiPath --out $configPath
    $godotExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    if ($godotExit -ne 0) {
        throw "MIDI 解析失败，Godot 退出码: $godotExit"
    }
} else {
    $configPath = Resolve-InputFile $Config '音乐配置 JSON'
}

try {
    $musicDocument = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
} catch {
    throw "音乐配置 JSON 无法读取: $configPath"
}
if ($null -eq $musicDocument.music -or $null -eq $musicDocument.music.segments) {
    throw "音乐配置缺少 music.segments: $configPath"
}
$expectedSegmentCount = @($musicDocument.music.segments).Count

& $godotExe --headless --no-header --path $repoRoot --script $cli -- `
    generate --kind music --config $configPath --out $mainC
$godotExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($godotExit -ne 0) {
    throw "音乐代码生成失败，Godot 退出码: $godotExit"
}
if (!(Test-Path -LiteralPath $mainC -PathType Leaf)) {
    throw "音乐代码生成后没有得到 main.c: $mainC"
}
$generatedCode = Get-Content -LiteralPath $mainC -Raw
if ($generatedCode -notmatch ('MUSIC_SEGMENT_COUNT\s+' + $expectedSegmentCount)) {
    throw "音乐代码与配置片段数不一致，生成可能失败: $mainC"
}

$buildScript = Join-Path $PSScriptRoot 'build.ps1'
$buildArgs = @{
    Project = $Project
    OutputRoot = $OutputRoot
}
if (-not [string]::IsNullOrWhiteSpace($Sdcc)) {
    $buildArgs.Sdcc = $Sdcc
}
if (-not [string]::IsNullOrWhiteSpace($LibDir)) {
    $buildArgs.LibDir = $LibDir
}
if (-not [string]::IsNullOrWhiteSpace($StdInclude)) {
    $buildArgs.StdInclude = $StdInclude
}
& $buildScript @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "SDCC 音乐工程构建失败，退出码: $LASTEXITCODE"
}
