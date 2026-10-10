# 用仓库内置 SDCC MCS-251 工具链构建 FreeRTOS STC32G12K128 演示固件。
#
# 用法:
#   pwsh .\freertos\build.ps1
#   pwsh .\freertos\build.ps1 -Project FREERTOS_DEMO
#   pwsh .\freertos\build.ps1 -Sdcc .\vendor\sdcc-toolchain\bin\sdcc.exe `
#       -LibDir .\vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
#       -StdInclude .\vendor\sdcc-toolchain\include
#
# 与 build.sh 共用 tools/build_firmware.py，仅做参数转发。

[CmdletBinding()]
param(
    [string]$Project,
    [switch]$All,
    [string]$Sdcc = $env:SDCC,
    [string]$LibDir = $env:SDCC_LIB_DIR,
    [string]$StdInclude = $env:SDCC_INCLUDE_DIR,
    [string]$Output
)

$ErrorActionPreference = 'Stop'

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw '找不到 python，无法执行构建脚本。'
}

$arguments = @((Join-Path $PSScriptRoot 'tools\build_firmware.py'))
if (![string]::IsNullOrWhiteSpace($Project)) { $arguments += @('--project', $Project) }
if ($All) { $arguments += '--all' }
if (![string]::IsNullOrWhiteSpace($Sdcc)) { $arguments += @('--sdcc', $Sdcc) }
if (![string]::IsNullOrWhiteSpace($LibDir)) { $arguments += @('--lib-dir', $LibDir) }
if (![string]::IsNullOrWhiteSpace($StdInclude)) { $arguments += @('--std-include', $StdInclude) }
if (![string]::IsNullOrWhiteSpace($Output)) { $arguments += @('--output', $Output) }

& $python.Source @arguments
exit $LASTEXITCODE
