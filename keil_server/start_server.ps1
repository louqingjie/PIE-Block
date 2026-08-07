# keil_server 一键启动脚本（本机作为编译服务器）
#
# 用法：
#   .\keil_server\start_server.ps1                          # 只监听本机；自动生成随机管理员 key
#   .\keil_server\start_server.ps1 -HostAll                 # 监听 0.0.0.0（局域网可访问，需放行防火墙）
#   .\keil_server\start_server.ps1 -Port 9000               # 自定义端口
#   .\keil_server\start_server.ps1 -ApiKey "abc123"         # 用你指定的管理员 key
#   .\keil_server\start_server.ps1 -ApiKey "abc123" -ApiKeys "张三:key1,李四:key2"  # 附带初始队员
#   .\keil_server\start_server.ps1 -NoAuth                  # 显式开放模式（无鉴权，仅本机/可信局域网）
#   .\keil_server\start_server.ps1 -NoKill                   # 端口被本服务旧实例占用时不自动停止，直接报错
#
# 默认（不传 -NoAuth）：会自动生成随机管理员 key 并打印，避免误开成无鉴权模式。
# 端口预检：若端口已被本服务旧实例（python/uvicorn）占用，自动停止后重启；
# 若是其他程序占用则报错退出（不误杀）；-NoKill 可禁用自动停止。
#
# 启动前自动检查：
#   1) 项目 .venv 存在且装好了依赖
#   2) 本机有可用的 Keil C251（C:\Keil_v5 等）
# 检查通过后前台运行 uvicorn（Ctrl+C 停止）。

param(
    [switch]$HostAll = $false,
    [int]$Port = 8000,
    [string]$ApiKey = "",
    [string]$ApiKeys = "",      # 可选：初始用户 key，格式 user:key,user:key
    [switch]$NoAuth = $false,    # 显式开放模式（不设鉴权）
    [switch]$NoKill = $false     # 端口被本服务旧实例占用时不自动停止
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

# ---- 3. 端口预检：端口被占用时处理旧实例 ----
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $oldPid = $existing.OwningProcess
    $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if (-not $oldProc) {
        Write-Host "[错误] 端口 $Port 被占用，但无法识别进程（PID $oldPid）。请手动检查。" -ForegroundColor Red
        exit 1
    }
    $isOurs = $oldProc.ProcessName -like "python*"
    if (-not $isOurs) {
        Write-Host "[错误] 端口 $Port 已被其他程序占用（$($oldProc.ProcessName)，PID $oldPid）。" -ForegroundColor Red
        Write-Host "       为避免误杀他人程序，不自动停止。请先结束它，或用 -Port 换端口。" -ForegroundColor Yellow
        exit 1
    }
    if ($NoKill) {
        Write-Host "[错误] 端口 $Port 已被本服务旧实例占用（PID $oldPid），且指定了 -NoKill。" -ForegroundColor Red
        Write-Host "       请先手动停止旧实例，或去掉 -NoKill 让脚本自动重启。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[提示] 检测到旧服务实例（PID $oldPid），自动停止后重启..." -ForegroundColor Yellow
    taskkill /F /T /PID $oldPid 2>&1 | Out-Null
    Start-Sleep -Milliseconds 800
}

# ---- 4. 鉴权设置与启动服务 ----
$hostBind = if ($HostAll) { "0.0.0.0" } else { "127.0.0.1" }

# 先清掉可能残留的旧 key，避免串台
Remove-Item Env:KEIL_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:KEIL_API_KEYS -ErrorAction SilentlyContinue

if ($NoAuth) {
    Write-Host "[警告] 以开放模式启动（无鉴权）——仅限本机/可信局域网使用！" -ForegroundColor Yellow
} else {
    if (-not $ApiKey) {
        # 未指定管理员 key -> 自动生成一个随机的并打印
        $ApiKey = (& $py -c "import secrets; print(secrets.token_urlsafe(12))").Trim()
        Write-Host "[OK] 已自动生成管理员 key：$ApiKey" -ForegroundColor Green
        Write-Host "     请保存好；队员各自用分配的用户 key。" -ForegroundColor Cyan
    } else {
        Write-Host "[OK] 已启用 API Key 鉴权（管理员 key = 你指定的）" -ForegroundColor Green
    }
    $env:KEIL_API_KEY = $ApiKey
    if ($ApiKeys) {
        $env:KEIL_API_KEYS = $ApiKeys
        Write-Host "[OK] 已注入初始用户 key（KEIL_API_KEYS）" -ForegroundColor Green
    }
}

Write-Host "启动编译服务: http://$hostBind`:$Port （Ctrl+C 停止）" -ForegroundColor Cyan
if ($HostAll) {
    Write-Host "注意：监听 0.0.0.0 需要防火墙放行 TCP $Port 端口，且局域网内其他机器才能访问。" -ForegroundColor Yellow
}
if ($NoAuth -and $HostAll) {
    Write-Host "警告：开放模式 + 监听 0.0.0.0 非常危险，不建议公网/跨网段使用！" -ForegroundColor Red
}
& $py -m uvicorn keil_server.server:app --host $hostBind --port $Port
