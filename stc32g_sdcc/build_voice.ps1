# 一条命令跑完 BUZZER_VOICE_SMOKE 的完整链路：
#   1. 用系统中文 TTS 生成参考音（render_reference.ps1）
#   2. LPC-10 分析 + 8 位量化，生成参数表与试听预览（make_voice_params.py）
#   3. 定点模型校验，含 C 与 Python 逐样本比对（check_voice_model.py）
#   4. SDCC 构建固件（build.ps1）
#
# 例：
#   pwsh .\stc32g_sdcc\build_voice.ps1 -Sdcc .\vendor\sdcc-toolchain\bin\sdcc.exe `
#     -LibDir .\vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
#     -StdInclude .\vendor\sdcc-toolchain\include
[CmdletBinding()]
param(
    [string]$Sdcc = $env:SDCC,
    [string]$LibDir = $env:SDCC_LIB_DIR,
    [string]$StdInclude = $env:SDCC_INCLUDE_DIR,
    [string]$Python = 'python',
    [string]$PreviewDir,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$project = Join-Path $root 'projects\BUZZER_VOICE_SMOKE'
$config = Join-Path $project 'voice.json'
if (!(Test-Path -LiteralPath $config)) { throw "缺少语料配置: $config" }
if ([string]::IsNullOrWhiteSpace($PreviewDir)) {
    $PreviewDir = Join-Path (Split-Path -Parent $root) 'output\试听\voice'
}

# numpy 是分析脚本的硬依赖：PATH 上的 python 未必带它，先给出明确提示。
& $Python -c 'import numpy' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "python 缺少 numpy: $Python。用 -Python 指定带 numpy 的解释器。"
}

$spec = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
$referenceDir = Join-Path $root 'build\voice_ref'
New-Item -ItemType Directory -Force -Path $referenceDir | Out-Null

$render = Join-Path $root 'tools\voice\render_reference.ps1'
foreach ($utterance in $spec.utterances) {
    & $render -Text $utterance.text -Out (Join-Path $referenceDir ($utterance.name + '_ref.wav')) `
        -VoiceCulture $spec.voice_culture -SampleRate $spec.reference_sample_rate
}

$paramsJson = Join-Path $root ('build\BUZZER_VOICE_SMOKE\voice_params.json')
& $Python (Join-Path $root 'tools\voice\make_voice_params.py') `
    --config $config `
    --ref-dir $referenceDir `
    --out-c (Join-Path $project 'src\voice_data.c') `
    --out-h (Join-Path $project 'inc\voice_data.h') `
    --params-json $paramsJson `
    --preview-dir $PreviewDir
if ($LASTEXITCODE -ne 0) { throw "参数生成失败，退出码 $LASTEXITCODE" }

& $Python (Join-Path $root 'tools\voice\check_voice_model.py') --params-json $paramsJson
if ($LASTEXITCODE -ne 0) { throw "定点模型校验失败，退出码 $LASTEXITCODE" }

if ($SkipBuild) {
    Write-Host '[SKIP] 已跳过 SDCC 构建'
    return
}
if ([string]::IsNullOrWhiteSpace($Sdcc)) {
    throw '未指定 SDCC：请用 -Sdcc 或设置 SDCC 环境变量。'
}

$buildArgs = @{ Project = 'BUZZER_VOICE_SMOKE'; Sdcc = $Sdcc }
if (![string]::IsNullOrWhiteSpace($LibDir)) { $buildArgs['LibDir'] = $LibDir }
if (![string]::IsNullOrWhiteSpace($StdInclude)) { $buildArgs['StdInclude'] = $StdInclude }
& (Join-Path $root 'build.ps1') @buildArgs
if ($LASTEXITCODE -ne 0) { throw "SDCC 构建失败，退出码 $LASTEXITCODE" }
