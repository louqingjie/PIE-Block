# keil_server 一键启动脚本（本机作为编译服务器）
#
# 用法：
#   .\keil_server\start_server.ps1                 # 只监听本机 127.0.0.1:8000
#   .\keil_server\start_server.ps1 -HostAll        # 监听 0.0.0.0（局域网可访问，需放行防火墙）
#   .\keil_server\start_server.ps1 -Port 9000      # 自定义端口
#   .\keil_server\start_server.ps1 -ApiKey "abc123"  # 启用 API Key 鉴权（公网部署必须）
#
# 启动前自动检查：
#   1) 项目 .venv 存在且装好了依赖
#   2) 本机有可用的 Keil C251（C:\Keil_v5 等）
# 检查通过后前台运行 uvicorn（Ctrl+C 停止）。

param(
    [switch]$HostAll = $false,
    [int]$Port = 8000,
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # keil_server 的上一级 = 项目根
Set-Location $root

# ---- 1. 检查 .venv ----
$py = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "[错误] 找不到 $py" -ForegroundColor Red
    Write-Host "请先创建虚拟环境并安装依赖：" -ForegroundColor Yellow
    Write-Host "  python -m venv .venv"
    Write-Host "  .\.venv\Scripts\python.exe -m pip install -r keil_server/requirements.txt"
    exit 1
}

# ---- 2. 检查 Keil 是否可用 ----
& $py -c "from keil_server import keil_detect; i=keil_detect.detect(); print('OK' if i.available else i.reason); raise SystemExit(0 if i.available else 1)"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 未找到可用的 Keil C251，编译服务无法工作。" -ForegroundColor Red
    Write-Host "请在本机安装完整版 Keil C251（如 C:\Keil_v5）并配置许可证。" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Keil C251 可用" -ForegroundColor Green

# ---- 3. 启动服务 ----
$hostBind = if ($HostAll) { "0.0.0.0" } else { "127.0.0.1" }
if ($ApiKey) {
    $env:KEIL_API_KEY = $ApiKey
    Write-Host "[OK] 已启用 API Key 鉴权（KEIL_API_KEY）" -ForegroundColor Green
}
Write-Host "启动编译服务: http://$hostBind`:$Port （Ctrl+C 停止）" -ForegroundColor Cyan
if ($HostAll) {
    Write-Host "注意：监听 0.0.0.0 需要防火墙放行 TCP $Port 端口，且局域网内其他机器才能访问。" -ForegroundColor Yellow
}
if (-not $ApiKey -and $HostAll) {
    Write-Host "警告：未设置 -ApiKey，服务处于开放模式，公网部署时必须加上。" -ForegroundColor Yellow
}
& $py -m uvicorn keil_server.server:app --host $hostBind --port $Port
