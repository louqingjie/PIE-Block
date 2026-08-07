# 恢复编译服务器（stop_server.ps1 的逆操作）：
# 启动 PieBlockKeil / PieBlockTunnel，恢复开机自启，重新启用健康监控任务。
#
# 用法（管理员 PowerShell）：
#   .\keil_server\deploy\start_server.ps1
#
# 可选参数：
#   -NssmExe   NSSM 路径（默认 C:\nssm\nssm.exe）
#   -Port      编译服务端口（默认 8000，用于健康检查验证）

param(
    [string]$NssmExe = "C:\nssm\nssm.exe",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$KeilServiceName = "PieBlockKeil"
$TunnelServiceName = "PieBlockTunnel"

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

# ---- 1. 服务改回自动启动并启动 ----
foreach ($svc in @($KeilServiceName, $TunnelServiceName)) {
    $code = Invoke-Nssm @("set", $svc, "Start", "SERVICE_AUTO_START")
    if ($code -eq 0) {
        Write-Host "[OK] $svc 启动类型已恢复为自动" -ForegroundColor Green
    } else {
        Write-Host "[警告] 修改 $svc 启动类型失败（退出码 $code）" -ForegroundColor Yellow
    }
    $code = Invoke-Nssm @("start", $svc)
    if ($code -eq 0) {
        Write-Host "[OK] $svc 已启动" -ForegroundColor Green
    } else {
        Write-Host "[警告] $svc 启动失败（退出码 $code）" -ForegroundColor Yellow
    }
}

# ---- 2. 验证健康检查 ----
Start-Sleep -Seconds 3
try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$Port/health"
    if ($r.StatusCode -eq 200 -and ($r.Content | ConvertFrom-Json).status -eq "ok") {
        Write-Host "[OK] 健康检查通过：http://127.0.0.1:$Port/health" -ForegroundColor Green
    } else {
        Write-Host "[警告] /health 返回异常（HTTP $($r.StatusCode)）" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[警告] /health 不可达，请检查 $PSScriptRoot\..\data\logs\keil-err.log" -ForegroundColor Yellow
}

# ---- 3. 恢复健康监控任务 ----
try {
    Enable-ScheduledTask -TaskName "PieBlockHealthMonitor" -ErrorAction Stop | Out-Null
    Write-Host "[OK] 健康监控任务已恢复" -ForegroundColor Green
} catch {
    Write-Host "[提示] PieBlockHealthMonitor 不存在或已启用（可忽略）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[完成] 编译服务器已恢复运行，开机自启 + 崩溃自动重启均已生效" -ForegroundColor Green
