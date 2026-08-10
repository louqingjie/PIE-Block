# 把 keil_server（编译服务）与 cloudflared（公网隧道）安装为 NSSM Windows 服务，
# 实现：崩溃自动重启、开机自启、日志落盘与轮转。
#
# 前提：
#   1. 已下载 NSSM：https://nssm.cc/download （默认放 C:\nssm\nssm.exe）
#   2. 已按 docs/公网部署CloudflareTunnel指南.md 配好隧道（跳过公网可加 -SkipTunnel）
#   3. 以「管理员」身份运行 PowerShell
#
# 用法（管理员 PowerShell，从项目根）：
#   .\keil_server\deploy\install_nssm.ps1
#   .\keil_server\deploy\install_nssm.ps1 -ApiKey "管理员密钥" -ApiKeys "user1:key1,user2:key2"
#   .\keil_server\deploy\install_nssm.ps1 -SkipTunnel -Port 8000
#
# 可选参数：
#   -NssmExe         NSSM 路径（默认 C:\nssm\nssm.exe）
#   -ApiKey          管理员 key（不填则从 keil_server\data\admin_key.txt 读，没有再自动生成）
#   -ApiKeys         初始用户 key，格式 user:key,user:key
#   -KeilPath        Keil 根目录（不填则自动探测 C:\Keil_v5 等常见路径）
#   -SkipTunnel      不安装 cloudflared 隧道服务（仅内网/本机用）
#   -TunnelName      隧道名（默认 pieblock）
#   -CloudflaredExe  cloudflared 路径（默认 C:\cloudflared\cloudflared.exe）
#   -Port            编译服务端口（默认 8000）
#
# 重复运行安全：服务已存在时先停止并删除再重建（幂等）。
# 卸载用 uninstall_nssm.ps1。

param(
    [string]$NssmExe = "C:\nssm\nssm.exe",
    [string]$ApiKey = "",
    [string]$ApiKeys = "",
    [string]$KeilPath = "",
    [switch]$SkipTunnel,
    [string]$TunnelName = "pieblock",
    [string]$CloudflaredExe = "C:\cloudflared\cloudflared.exe",
    [int]$Port = 8000,
    [string]$BuildUser = "",
    [string]$BuildPassword = ""
)

$ErrorActionPreference = "Stop"
$KeilServiceName = "PieBlockKeil"
$TunnelServiceName = "PieBlockTunnel"

# 项目根：本脚本在 keil_server\deploy\ 下
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$py = Join-Path $root ".venv\Scripts\python.exe"
$dataDir = Join-Path $root "keil_server\data"
$logDir = Join-Path $dataDir "logs"

# nssm 的 banner/提示常写到 stderr；Windows PowerShell 5.1 中
# $ErrorActionPreference="Stop" 时原生命令的 stderr 输出会抛终止错误（2>$null 也挡不住），
# 所以所有 nssm 调用统一走这里：吞掉错误流，用 $LASTEXITCODE 判断真实成败。
# 注意：不要在脚本里跑 `nssm version` 做可用性检查——它在非控制台环境下会挂起/返回异常退出码。
function Invoke-Nssm {
    param([string[]]$ArgsList)
    $exit = -1
    try {
        & $NssmExe @ArgsList 2>$null | Out-Null
        $exit = $LASTEXITCODE
    } catch {
        $exit = $LASTEXITCODE
    }
    return $exit
}

function Say-Info([string]$msg)  { Write-Host $msg -ForegroundColor Cyan }
function Say-Ok([string]$msg)    { Write-Host $msg -ForegroundColor Green }
function Say-Warn([string]$msg)  { Write-Host $msg -ForegroundColor Yellow }
function Say-Err([string]$msg)   { Write-Host $msg -ForegroundColor Red }

# ---- 0. 校验 NSSM（仅文件存在性；nssm version 在非控制台环境会挂起，勿用） ----
if (-not (Test-Path $NssmExe)) {
    Say-Err "[错误] 找不到 NSSM：$NssmExe"
    Write-Host "       请到 https://nssm.cc/download 下载，把 nssm.exe 放到该位置（或传 -NssmExe 指定路径）" -ForegroundColor Yellow
    exit 1
}

# ---- 1. 校验 .venv ----
if (-not (Test-Path $py)) {
    Say-Err "[错误] 找不到 $py，请先创建 .venv 并 pip install -r keil_server/requirements.txt"
    exit 1
}

# ---- 2. Keil 路径：-KeilPath > 自动探测 ----
$candidates = @("C:\Keil_v5")
if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Keil_v5") }
$candidates += "C:\Keil"
if (-not $KeilPath) {
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "UV4\UV4.exe")) { $KeilPath = $c; break }
    }
}
# 注意：服务以 SYSTEM 账号运行，看不到你的用户环境变量，所以 KEIL_PATH 必须显式固化
if ($KeilPath) {
    Say-Ok "[OK] 使用 Keil 目录：$KeilPath（会写入服务环境变量）"
} else {
    Say-Warn "[警告] 未找到完整版 Keil（C:\Keil_v5 等），服务将使用自动探测（含项目内精简工具链，仅限开发验证）"
    Write-Host "       生产部署请装正版 Keil C251 后重跑本脚本，或用 -KeilPath 指定" -ForegroundColor Yellow
}

# ---- 3. 管理员 key 解析（-ApiKey 参数 > 本地文件 > 自动生成并保存） ----
$adminKeyFile = Join-Path $dataDir "admin_key.txt"
if (-not $ApiKey -and (Test-Path $adminKeyFile)) {
    $ApiKey = (Get-Content $adminKeyFile -Raw).Trim()
    Say-Ok "[OK] 已从本地文件加载管理员 key（$adminKeyFile）"
} elseif (-not $ApiKey) {
    $ApiKey = (& $py -c "import secrets; print(secrets.token_urlsafe(12))").Trim()
    try {
        if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
        [IO.File]::WriteAllText($adminKeyFile, $ApiKey, (New-Object System.Text.UTF8Encoding $false))
        Say-Ok "[OK] 已生成并保存管理员 key：$ApiKey"
        Say-Info "     已写入 $adminKeyFile（data/ 已 gitignore，不进仓库）"
    } catch {
        Say-Ok "[OK] 已生成管理员 key（未保存文件）：$ApiKey"
    }
} else {
    Say-Ok "[OK] 已启用 API Key 鉴权（管理员 key = 你指定的）"
}

# ---- 4. 编译降权用户：仅 -BuildUser 显式启用（默认不降权，编译以服务账户运行）。
#       内部工具场景直接 SYSTEM 跑即可；要隔离恶意工程时传 -BuildUser/-BuildPassword。
if ($BuildUser -and $BuildPassword) {
    Say-Ok "[OK] 已启用编译降权用户：$BuildUser"
} elseif ($BuildUser) {
    Say-Warn "[警告] 指定了 -BuildUser 但未提供 -BuildPassword，降权不生效"
} else {
    Say-Info "[信息] 未启用编译降权（编译以服务账户 SYSTEM 运行）"
}

# ---- 5. 日志目录 ----
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# ---- 5. 端口预检：端口被旧实例（手动启动的 python）占用时自动停止，
#      否则新服务 bind 失败会陷入"退出→重启"循环 ----
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    $oldPid = $existing.OwningProcess
    $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($oldProc -and $oldProc.ProcessName -like "python*") {
        Say-Warn "[提示] 检测到旧服务实例（PID $oldPid），自动停止后重建服务..."
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
    } else {
        Say-Err "[错误] 端口 $Port 已被其他程序占用（PID $oldPid）。请先处理后再运行本脚本。"
        exit 1
    }
}

# ---- 6. 移除旧服务（幂等重建） ----
foreach ($svc in @($KeilServiceName, $TunnelServiceName)) {
    $null = Invoke-Nssm @("stop", $svc)
    $null = Invoke-Nssm @("remove", $svc, "confirm")
}

# ---- 6. 安装 keil_server 服务 ----
Say-Info "[1/2] 安装编译服务 PieBlockKeil ..."
$code = Invoke-Nssm @("install", $KeilServiceName, $py, "-m", "uvicorn", "keil_server.server:app", "--host", "127.0.0.1", "--port", "$Port")
if ($code -ne 0) { Say-Err "[错误] nssm install 编译服务失败（退出码 $code）"; exit 1 }
$null = Invoke-Nssm @("set", $KeilServiceName, "AppDirectory", $root)
# 环境变量：SYSTEM 账号没有用户环境，必须全部显式传
$envArgs = @("KEIL_API_KEY=$ApiKey")
if ($ApiKeys)  { $envArgs += "KEIL_API_KEYS=$ApiKeys" }
if ($KeilPath) { $envArgs += "KEIL_PATH=$KeilPath" }
if ($BuildUser -and $BuildPassword) {
    $envArgs += "KEIL_BUILD_USER=$BuildUser"
    $envArgs += "KEIL_BUILD_PASSWORD=$BuildPassword"
}
$envSet = @("set", $KeilServiceName, "AppEnvironmentExtra") + @($envArgs)
$null = Invoke-Nssm $envSet
# 崩溃自动重启 + 日志轮转
$null = Invoke-Nssm @("set", $KeilServiceName, "AppExit", "Default", "Restart")
$null = Invoke-Nssm @("set", $KeilServiceName, "AppRestartDelay", "5000")
$null = Invoke-Nssm @("set", $KeilServiceName, "AppThrottle", "1500")
$null = Invoke-Nssm @("set", $KeilServiceName, "AppStdout", (Join-Path $logDir "keil-out.log"))
$null = Invoke-Nssm @("set", $KeilServiceName, "AppStderr", (Join-Path $logDir "keil-err.log"))
$null = Invoke-Nssm @("set", $KeilServiceName, "AppRotateFiles", "1")
$null = Invoke-Nssm @("set", $KeilServiceName, "AppRotateBytes", "1048576")
$null = Invoke-Nssm @("set", $KeilServiceName, "Start", "SERVICE_AUTO_START")
$null = Invoke-Nssm @("start", $KeilServiceName)
Say-Ok "[OK] 编译服务已启动（服务名 $KeilServiceName，日志在 $logDir）"

# ---- 7. 验证 /health ----
Start-Sleep -Seconds 3
$healthy = $false
try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$Port/health"
    if ($r.StatusCode -eq 200 -and ($r.Content | ConvertFrom-Json).status -eq "ok") {
        $healthy = $true
    }
} catch {
    $healthy = $false
}
if ($healthy) {
    Say-Ok "[OK] 健康检查通过：http://127.0.0.1:$Port/health"
} else {
    Say-Warn "[警告] 服务已启动但 /health 未通过，请检查 $logDir\keil-err.log"
}

# ---- 8. 安装 cloudflared 隧道服务（可选） ----
if ($SkipTunnel) {
    Say-Info "[2/2] 已跳过 cloudflared 隧道（-SkipTunnel），仅本机/内网使用"
} else {
    if (-not (Test-Path $CloudflaredExe)) {
        Say-Warn "[警告] 找不到 cloudflared：$CloudflaredExe，跳过隧道安装（不影响编译服务）"
        Write-Host "       需要公网请下载：https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" -ForegroundColor Yellow
    } else {
        $tunnelCfg = Join-Path $PSScriptRoot "cloudflared-config.yml"
        if (-not (Test-Path $tunnelCfg)) {
            Say-Warn "[警告] 缺少隧道配置 $tunnelCfg，跳过隧道安装"
        } else {
            Say-Info "[2/2] 安装公网隧道 $TunnelServiceName ..."
            # 注意：--config / --protocol 必须放在 run 之前
            $code = Invoke-Nssm @("install", $TunnelServiceName, $CloudflaredExe, "tunnel", "--config", $tunnelCfg, "--protocol", "http2", "run", $TunnelName)
            if ($code -ne 0) { Say-Err "[错误] nssm install 隧道失败（退出码 $code）"; exit 1 }
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppDirectory", (Split-Path $CloudflaredExe))
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppExit", "Default", "Restart")
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppRestartDelay", "5000")
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppThrottle", "1500")
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppStdout", (Join-Path $logDir "tunnel-out.log"))
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppStderr", (Join-Path $logDir "tunnel-err.log"))
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppRotateFiles", "1")
            $null = Invoke-Nssm @("set", $TunnelServiceName, "AppRotateBytes", "1048576")
            $null = Invoke-Nssm @("set", $TunnelServiceName, "Start", "SERVICE_AUTO_START")
            $null = Invoke-Nssm @("start", $TunnelServiceName)
            Say-Ok "[OK] 隧道服务已启动（服务名 $TunnelServiceName）"
        }
    }
}

# ---- 9. 摘要 ----
Say-Info ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " 两个服务均崩溃自动重启 + 开机自启" -ForegroundColor Green
Write-Host " 下一步（建议）：注册健康监控与每日备份计划任务" -ForegroundColor Green
Write-Host "   .\keil_server\deploy\install_scheduled_tasks.ps1" -ForegroundColor Cyan
if (-not $SkipTunnel) {
    Write-Host " 公网地址：https://build.pieblock.asia/health" -ForegroundColor Green
    Write-Host " 客户端：PIEBLOCK_KEIL_SERVER_URL=https://build.pieblock.asia / PIEBLOCK_KEIL_API_KEY=$ApiKey" -ForegroundColor Green
}
Write-Host "======================================================" -ForegroundColor Green
