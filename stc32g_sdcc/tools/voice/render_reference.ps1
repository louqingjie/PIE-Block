# 用 Windows 内置 SAPI 中文语音合成“金标准”参考音，供 LPC-10 参数提取使用。
#
# 该步骤只在主机侧运行，不参与固件构建；产物写入 build/ 等忽略目录即可。
# System.Speech 只随 Windows PowerShell 5.1 提供（PowerShell 7 需要额外包），
# 所以在 PS7 下会自动改用 powershell.exe 重新调用本脚本。
[CmdletBinding()]
param(
    [string]$Text,
    [string]$TextFile,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$VoiceCulture = 'zh-CN',
    [int]$SampleRate = 8000
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (!(Test-Path -LiteralPath $windowsPowerShell)) {
        throw "找不到 Windows PowerShell: $windowsPowerShell"
    }
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Out', $Out,
        '-VoiceCulture', $VoiceCulture, '-SampleRate', $SampleRate)
    if (![string]::IsNullOrWhiteSpace($TextFile)) { $forward += @('-TextFile', $TextFile) }
    elseif (![string]::IsNullOrWhiteSpace($Text)) { $forward += @('-Text', $Text) }
    else { throw '必须提供 -Text 或 -TextFile。' }
    & $windowsPowerShell @forward
    if ($LASTEXITCODE -ne 0) { throw "Windows PowerShell 渲染失败，退出码 $LASTEXITCODE" }
    return
}

if (![string]::IsNullOrWhiteSpace($TextFile)) {
    $Text = (Get-Content -LiteralPath $TextFile -Raw -Encoding UTF8).Trim()
}
if ([string]::IsNullOrWhiteSpace($Text)) { throw '合成文本为空。' }

Add-Type -AssemblyName System.Speech

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voiceName = $null
try {
    $voice = $synth.GetInstalledVoices() | Where-Object {
        $_.Enabled -and $_.VoiceInfo.Culture.Name -like ($VoiceCulture + '*')
    } | Select-Object -First 1
    if ($null -eq $voice) {
        $available = ($synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }) -join ', '
        throw "没有 $VoiceCulture 语音；已安装: $available"
    }
    $voiceName = $voice.VoiceInfo.Name
    $synth.SelectVoice($voiceName)
    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
        $SampleRate,
        [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
        [System.Speech.AudioFormat.AudioChannel]::Mono)
    $directory = Split-Path -Parent $Out
    if (![string]::IsNullOrEmpty($directory) -and !(Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $synth.SetOutputToWaveFile($Out, $format)
    $synth.Speak($Text)
}
finally {
    $synth.Dispose()
}

Write-Host ("[TTS] " + $voiceName + " " + $SampleRate + "Hz -> " + $Out)
