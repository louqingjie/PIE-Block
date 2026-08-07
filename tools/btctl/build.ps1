# btctl 构建脚本
# 用法（在工作区根目录或本目录）：
#   powershell -ExecutionPolicy Bypass -File tools/btctl/build.ps1          # 框架依赖（需要目标机有 .NET 8 运行时）
#   powershell -ExecutionPolicy Bypass -File tools/btctl/build.ps1 -SelfContained  # 自包含（学生机免装 .NET，体积 ~70MB）
param(
    [switch]$SelfContained
)
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$out  = Join-Path $root "out"
$self = if ($SelfContained) { "true" } else { "false" }

Write-Host "==> dotnet publish btctl (selfContained=$self) ..."
dotnet publish (Join-Path $root "btctl.csproj") `
    -c Release -r win-x64 --self-contained $self `
    -p:PublishSingleFile=true -p:PublishTrimmed=false `
    -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish 失败，退出码 $LASTEXITCODE" }

$exe = Join-Path $out "btctl.exe"
if (-not (Test-Path $exe)) { throw "未找到产物: $exe" }
Write-Host ""
Write-Host "OK  输出: $exe"
Write-Host "     框架依赖产物需要目标机已装 .NET 8 运行时（本开发机已装）。"
Write-Host "     给学生的最终发布用 build.ps1 -SelfContained 出单文件自包含版。"
