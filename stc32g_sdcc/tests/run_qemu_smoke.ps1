[CmdletBinding()]
param(
    [string]$Qemu = $env:QEMU_MCS251,
    [string]$Machine,
    [string]$Hex = (Join-Path $PSScriptRoot '..\build\minimal\qemu\qemu_smoke.hex'),
    [int]$TimeoutMilliseconds = 3000
)

$ErrorActionPreference = 'Stop'

function Resolve-Executable([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw '未指定 qemu-system-mcs251。请使用 -Qemu 或设置 QEMU_MCS251。'
    }
    if (Test-Path -LiteralPath $Name -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Name).Path
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "找不到 QEMU: $Name"
    }
    return $command.Source
}

$qemuPath = Resolve-Executable $Qemu
$hexPath = (Resolve-Path -LiteralPath $Hex).Path
if ([string]::IsNullOrWhiteSpace($Machine)) {
    $machineHelp = & $qemuPath -machine help 2>&1 | Out-String
    foreach ($candidate in @('stc32g144k246-evb', 'stc32g144k246')) {
        if ($machineHelp -match [regex]::Escape($candidate)) {
            $Machine = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Machine)) {
    throw 'QEMU 没有发现 stc32g144k246 或 stc32g144k246-evb 机器模型。'
}

$info = New-Object System.Diagnostics.ProcessStartInfo
$info.FileName = $qemuPath
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
foreach ($argument in @(
        '-M', $Machine, '-bios', $hexPath, '-accel', 'tcg',
        '-icount', 'shift=0,align=off,sleep=off', '-display', 'none',
        '-monitor', 'none', '-serial', 'stdio')) {
    $info.ArgumentList.Add($argument)
}

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $info
$null = $process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (!$process.WaitForExit($TimeoutMilliseconds)) {
    $process.Kill()
    $process.WaitForExit()
    throw "QEMU 在 ${TimeoutMilliseconds}ms 内没有输出 PASS。"
}
$output = $stdoutTask.Result + $stderrTask.Result
Write-Output $output
if ($output -notmatch '(?m)^PASS\s*$') {
    throw 'QEMU 没有输出独立的 PASS 行。'
}
Write-Host "[PASS] QEMU $Machine 执行 $hexPath"
