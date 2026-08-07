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
    [string]$ApiKey = "",          # 管理员 key（不填则从本地 data/admin_key.txt 读，没有再自动生成保存）
    [string]$ApiKeys = "",          # 可选：初始用户 key，格式 user:key,user:key（队员每人一把）
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

# ---- 3. 端口预检：端口被本服务旧实例占用时自动重启 ----
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $oldPid = $existing.OwningProcess
    $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($oldProc -and $oldProc.ProcessName -like "python*") {
        Write-Host "[提示] 检测到旧服务实例（PID $oldPid），自动停止后重启..." -ForegroundColor Yellow
        taskkill /F /T /PID $oldPid 2>&1 | Out-Null
        Start-Sleep -Milliseconds 800
    } else {
        Write-Host "[错误] 端口 $Port 已被其他程序占用（PID $oldPid）。请先处理。" -ForegroundColor Red
        exit 1
    }
}

# ---- 4. 管理员 key 解析（-ApiKey 参数 > 本地文件 > 自动生成并保存） ----
$adminKeyFile = Join-Path $root "keil_server\data\admin_key.txt"
if (-not $ApiKey -and (Test-Path $adminKeyFile)) {
    $ApiKey = (Get-Content $adminKeyFile -Raw).Trim()
    Write-Host "[OK] 已从本地文件加载管理员 key（$adminKeyFile）" -ForegroundColor Green
} elseif (-not $ApiKey) {
    $ApiKey = (& $py -c "import secrets; print(secrets.token_urlsafe(12))").Trim()
    try {
        $dir = Split-Path $adminKeyFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [IO.File]::WriteAllText($adminKeyFile, $ApiKey, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "[OK] 已生成并保存管理员 key：$ApiKey" -ForegroundColor Green
        Write-Host "     已写入 $adminKeyFile（data/ 已 gitignore，不进仓库）" -ForegroundColor Cyan
    } catch {
        Write-Host "[OK] 已生成管理员 key（未保存文件）：$ApiKey" -ForegroundColor Green
    }
} else {
    Write-Host "[OK] 已启用 API Key 鉴权（管理员 key = 你指定的）" -ForegroundColor Green
}

# ---- 5. 启动 keil_server（后台） ----
$env:KEIL_API_KEY = $ApiKey
if ($ApiKeys) { $env:KEIL_API_KEYS = $ApiKeys }
Write-Host "[1/2] 启动 keil_server (127.0.0.1:$Port, 多用户 API Key 鉴权已开)..." -ForegroundColor Cyan
$server = Start-Process -FilePath $py -ArgumentList @(
    "-m", "uvicorn", "keil_server.server:app",
    "--host", "127.0.0.1", "--port", "$Port"
) -WorkingDirectory $root -WindowStyle Hidden -PassThru
Write-Host "      编译服务 PID: $($server.Id)"

Start-Sleep -Seconds 3

# ---- 6. 启动 cloudflared 隧道（后台） ----
# 注意：--config / --protocol 必须放在 run 之前；用 --protocol http2（本机网络常拦 QUIC/7844，HTTP2 更稳）
Write-Host "[2/2] 启动 cloudflared 隧道 '$TunnelName' ..." -ForegroundColor Cyan
$tunnel = Start-Process -FilePath $CloudflaredExe -ArgumentList @(
    "tunnel", "--config", $cfg, "--protocol", "http2", "run", $TunnelName
) -WorkingDirectory (Split-Path $CloudflaredExe) -WindowStyle Hidden -PassThru
Write-Host "      cloudflared PID: $($tunnel.Id)"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " 公网地址：https://build.pieblock.asia/health" -ForegroundColor Green
Write-Host " 客户端配置：PIEBLOCK_KEIL_SERVER_URL=https://build.pieblock.asia" -ForegroundColor Green
Write-Host "             PIEBLOCK_KEIL_API_KEY=你的密钥" -ForegroundColor Green
Write-Host " 两个进程都以后台方式运行；关闭本机/结束进程即下线。" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green
