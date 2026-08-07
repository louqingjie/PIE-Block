# 一键启动公网编译服务：keil_server（带 API Key 鉴权）+ cloudflared 隧道
#
# 前提：已按 docs/公网部署CloudflareTunnel指南.md 完成一次性的
#   cloudflared 安装、login、tunnel create，并把
#   deploy/cloudflared-config.yml.example 复制为 cloudflared-config.yml 填好。
#
# 用法：
#   .\keil_server\deploy\start_public.ps1 -ApiKey "你的密钥"
# 可选：
#   -TunnelName "pieblock"       隧道名（默认 pieblock）
#   -CloudflaredExe "C:\cloudflared\cloudflared.exe"    cloudflared 路径
#   -Port 8000                   编译服务端口

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,                 # 公网鉴权密钥（必填，不能空）
    [string]$TunnelName = "pieblock",
    [string]$CloudflaredExe = "C:\cloudflared\cloudflared.exe",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # deploy 的上一级x2 = 项目根
Set-Location $root
$py = Join-Path $root ".venv\Scripts\python.exe"
$cfg = Join-Path $PSScriptRoot "cloudflared-config.yml"

# ---- 1. 校验 ----
if (-not $ApiKey -or $ApiKey -match "^\s*$") {
    Write-Host "[错误] 公网部署必须设置 -ApiKey（KEIL_API_KEY 鉴权）" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $py)) {
    Write-Host "[错误] 找不到 $py，请先创建 .venv 并装依赖" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $CloudflaredExe)) {
    Write-Host "[错误] 找不到 cloudflared：$CloudflaredExe" -ForegroundColor Red
    Write-Host "       请下载 https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $cfg)) {
    Write-Host "[错误] 缺少隧道配置 $cfg" -ForegroundColor Red
    Write-Host "       请复制 cloudflared-config.yml.example 为 cloudflared-config.yml 并填写" -ForegroundColor Yellow
    exit 1
}

# ---- 2. 校验本机 Keil 可用 ----
& $py -c "from keil_server import keil_detect; i=keil_detect.detect(); print('OK' if i.available else i.reason); raise SystemExit(0 if i.available else 1)"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 未找到可用的 Keil C251，编译服务无法工作" -ForegroundColor Red
    exit 1
}

# ---- 3. 启动 keil_server（后台） ----
$env:KEIL_API_KEY = $ApiKey
Write-Host "[1/2] 启动 keil_server (127.0.0.1:$Port, API Key 鉴权已开)..." -ForegroundColor Cyan
$server = Start-Process -FilePath $py -ArgumentList @(
    "-m", "uvicorn", "keil_server.server:app",
    "--host", "127.0.0.1", "--port", "$Port"
) -WorkingDirectory $root -WindowStyle Hidden -PassThru
Write-Host "      编译服务 PID: $($server.Id)"

Start-Sleep -Seconds 3

# ---- 4. 启动 cloudflared 隧道（后台） ----
Write-Host "[2/2] 启动 cloudflared 隧道 '$TunnelName' ..." -ForegroundColor Cyan
$tunnel = Start-Process -FilePath $CloudflaredExe -ArgumentList @(
    "tunnel", "run", $TunnelName, "--config", $cfg
) -WorkingDirectory (Split-Path $CloudflaredExe) -WindowStyle Hidden -PassThru
Write-Host "      cloudflared PID: $($tunnel.Id)"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " 公网地址：https://build.pieblock.asia/health" -ForegroundColor Green
Write-Host " 客户端配置：PIEBLOCK_KEIL_SERVER_URL=https://build.pieblock.asia" -ForegroundColor Green
Write-Host "             PIEBLOCK_KEIL_API_KEY=你的密钥" -ForegroundColor Green
Write-Host " 两个进程都以后台方式运行；关闭本机/结束进程即下线。" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green
