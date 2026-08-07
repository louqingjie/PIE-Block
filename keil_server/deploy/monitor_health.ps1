# 健康监控脚本：由计划任务每 60 秒调用一次（任务计划程序最小间隔为 1 分钟）。
# 检查编译服务 /health，连续失败多次后自动重启服务；
# 同时确保 cloudflared 隧道服务在运行（可选公网健康检查）。
#
# 由 install_scheduled_tasks.ps1 注册为计划任务 PieBlockHealthMonitor，
# 也可手动测试：
#   .\keil_server\deploy\monitor_health.ps1 -FailThreshold 1
#
# 可选参数：
#   -BaseUrl           健康检查 URL（完整路径，默认 http://127.0.0.1:8000/health）
#   -PublicUrl         公网地址（如 https://build.pieblock.asia/health），
#                      提供时每次也会探测，失败则重启隧道服务
#   -FailThreshold     连续失败多少次才重启（默认 3）
#   -TimeoutSeconds    单次探测超时（默认 10；公网 Cloudflare 首连可能 5~8 秒，
#                      5 秒太紧会误报）
#   -RestartCooldown   两次重启的最小间隔秒数（默认 60，防重启风暴）
#   -StateFile / -LogFile   状态计数与日志文件（默认在 keil_server\data\ 下）

param(
    [string]$BaseUrl = "http://127.0.0.1:8000/health",
    [string]$PublicUrl = "",
    [string]$KeilServiceName = "PieBlockKeil",
    [string]$TunnelServiceName = "PieBlockTunnel",
    [int]$FailThreshold = 3,
    [int]$TimeoutSeconds = 10,
    [int]$RestartCooldown = 60,
    [string]$StateFile = "",
    [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $StateFile) { $StateFile = Join-Path $root "keil_server\data\monitor_fail.txt" }
if (-not $LogFile)   { $LogFile = Join-Path $root "keil_server\data\logs\monitor.log" }
$logDir = Split-Path $LogFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Test-Health([string]$url) {
    # 返回 $true = 健康
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec $TimeoutSeconds $url
        return ($r.StatusCode -eq 200 -and ($r.Content | ConvertFrom-Json).status -eq "ok")
    } catch {
        return $false
    }
}

function Read-State() {
    # 状态文件两行：连续失败次数、上次重启时间戳（Unix 秒）
    $fail = 0
    $lastRestart = 0
    if (Test-Path $StateFile) {
        $lines = @(Get-Content $StateFile -ErrorAction SilentlyContinue)
        if ($lines.Count -ge 1) { [int]::TryParse($lines[0], [ref]$fail) | Out-Null }
        if ($lines.Count -ge 2) { [long]::TryParse($lines[1], [ref]$lastRestart) | Out-Null }
    }
    return @($fail, $lastRestart)
}

function Write-State([int]$fail, [long]$lastRestart) {
    @("$fail", "$lastRestart") | Set-Content -Path $StateFile -Encoding UTF8
}

# ---- 1. 编译服务健康检查 ----
$state = Read-State
$fail = $state[0]
$lastRestart = $state[1]

if (Test-Health $BaseUrl) {
    if ($fail -gt 0) {
        Write-Log "[恢复] 编译服务健康，重置失败计数（曾连续失败 $fail 次）"
    }
    Write-State 0 $lastRestart
} else {
    $fail++
    $now = [long](Get-Date -UFormat %s)
    Write-Log "[告警] /health 探测失败（第 $fail 次，共需 $FailThreshold 次）"
    if ($fail -ge $FailThreshold -and ($now - $lastRestart) -ge $RestartCooldown) {
        Write-Log "[动作] 连续失败 $fail 次，重启服务 $KeilServiceName"
        try {
            Restart-Service -Name $KeilServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            $lastRestart = [long](Get-Date -UFormat %s)
            if (Test-Health $BaseUrl) {
                Write-Log "[恢复] 重启后 /health 通过"
            } else {
                Write-Log "[严重] 重启后 /health 仍失败，请检查 $LogFile 同目录的 keil-err.log"
            }
        } catch {
            Write-Log "[错误] 重启服务失败（需要管理员权限运行计划任务）：$_"
            $lastRestart = [long](Get-Date -UFormat %s)   # 避免每次探测都尝试重启
        }
        Write-State 0 $lastRestart
    } else {
        Write-State $fail $lastRestart
    }
}

# ---- 2. 隧道服务存活检查 ----
$svc = Get-Service -Name $TunnelServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne "Running") {
        Write-Log "[动作] 隧道服务未运行（$($svc.Status)），尝试启动"
        try {
            Start-Service -Name $TunnelServiceName -ErrorAction Stop
            Write-Log "[恢复] 隧道服务已启动"
        } catch {
            Write-Log "[错误] 启动隧道服务失败：$_"
        }
    }
    # 公网探测（可选）：能通说明 隧道+域名+证书 全链路正常
    if ($PublicUrl) {
        if (-not (Test-Health $PublicUrl)) {
            Write-Log "[告警] 公网探测失败：$PublicUrl"
            if ($svc.Status -eq "Running") {
                Write-Log "[动作] 重启隧道服务 $TunnelServiceName"
                try {
                    Restart-Service -Name $TunnelServiceName -Force -ErrorAction Stop
                    Write-Log "[动作] 隧道服务已重启"
                } catch {
                    Write-Log "[错误] 重启隧道服务失败：$_"
                }
            }
        }
    }
}
