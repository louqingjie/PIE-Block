# 用系统中文识别器（SAPI 桌面识别引擎，MS-2052-80-DESK）离线识别 WAV，
# 作为“蜂鸣器合成语音能不能听懂”的客观验证手段。
#
# 默认用听写语法；给出 -Choices 时改用候选集语法，此时置信度是“最像哪一个”，
# 比听写更适合评估合成语音的可懂度。
#
# 注意两点：
#   * 该识别器前端按 16kHz 处理，喂 8kHz 音频会得到完全错误的结果，
#     所以输入应当是 16kHz 的 WAV（make_voice_params.py 会输出 *_16k.wav）。
#   * 必须传绝对路径：SetInputToWaveFile 走 .NET 当前目录，和 PowerShell 的
#     当前位置不是一回事。
#
# System.Speech 只随 Windows PowerShell 5.1 提供，PS7 下会自动用 powershell.exe
# 重新调用本脚本。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Wav,
    [string]$Culture = 'zh-CN',
    [string[]]$Choices,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
        '-Wav') + $Wav + @('-Culture', $Culture)
    if ($Choices) { $forward += @('-Choices') + $Choices }
    if ($Json) { $forward += '-Json' }
    & $windowsPowerShell @forward
    if ($LASTEXITCODE -ne 0) { throw "Windows PowerShell 识别失败，退出码 $LASTEXITCODE" }
    return
}

Add-Type -AssemblyName System.Speech

# 注意：SpeechRecognitionEngine(string) 的字符串参数是“识别器 ID”，不是区域名；
# 按区域选引擎必须传 CultureInfo。
$cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

function New-Engine {
    $engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine($cultureInfo)
    if ($Choices) {
        $choiceList = New-Object System.Speech.Recognition.Choices
        foreach ($item in $Choices) { $choiceList.Add($item) | Out-Null }
        $builder = New-Object System.Speech.Recognition.GrammarBuilder
        $builder.Append($choiceList)
        $engine.LoadGrammar((New-Object System.Speech.Recognition.Grammar($builder)))
    }
    else {
        $engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
    }
    return $engine
}

$report = @()
foreach ($path in $Wav) {
    $full = (Resolve-Path -LiteralPath $path).Path
    # 每个文件用新引擎：识别器复用时会保留上一次的音频位置，容易读不到输入。
    $engine = New-Engine
    $texts = @()
    $confidences = @()
    try {
        $engine.SetInputToWaveFile($full)
        while ($true) {
            $result = $engine.Recognize()
            if ($null -eq $result) { break }
            $texts += $result.Text
            $confidences += $result.Confidence
        }
    }
    catch {
        Write-Warning ("识别 " + (Split-Path -Leaf $full) + " 失败: " + $_.Exception.Message)
    }
    finally {
        $engine.Dispose()
    }
    $entry = [pscustomobject]@{
        wav        = $full
        recognized = ($texts -join '')
        segments   = $texts.Count
        confidence = if ($confidences.Count -gt 0) {
            [math]::Round(($confidences | Measure-Object -Average).Average, 3)
        } else { 0 }
    }
    $report += $entry
    if (-not $Json) {
        Write-Host ("[识别] " + (Split-Path -Leaf $full) + " -> '" + $entry.recognized +
            "' 段数=" + $entry.segments + " 平均置信度=" + $entry.confidence)
    }
}

if ($Json) { $report | ConvertTo-Json -Depth 4 }
