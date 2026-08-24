[CmdletBinding()]
param(
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$testRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
Push-Location $testRoot
try {
    & $Python -m unittest discover -s . -p 'test_*.py' -v
    if ($LASTEXITCODE -ne 0) {
        throw "主机侧单元测试失败，退出码 $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
