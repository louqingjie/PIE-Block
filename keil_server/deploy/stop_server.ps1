# 停止编译服务器（keil_server + cloudflared）并禁止开机自启。
# 服务保留不删除，随时可用 start_server.ps1 恢复。
#
# 用法（管理员 PowerShell）：
#   .\keil_server\deploy\stop_server.ps1
#
# 做的事：
#   1. 停止健康监控计划任务（否则探测失败会自动拉起服务，白停）
#   2. 停止 PieBlockKeil / PieBlockTunnel 两个服务
#   3. 服务启动类型改为手动（SERVICE_DEMAND_START，不再开机自启）
#
# 可选参数：
#   -NssmExe   NSSM 路径（默认 C:\nssm\nssm.exe）

param(
    [string]$NssmExe = "C:\nssm\nssm.exe"
)

$ErrorActionPreference = "Stop"
$KeilServiceName = "PieBlockKeil"
$TunnelServiceName = "PieBlockTunnel"

# 同 install_nssm.ps1：PS 5.1 下 EAP=Stop 时原生命令的 stderr 会抛终止错误
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

# ---- 1. 停监控任务 ----
foreach ($task in @("PieBlockHealthMonitor")) {
    try {
        Disable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
        Write-Host "[OK] 已停止健康监控任务 $task（防止自动拉起服务）" -ForegroundColor Green
    } catch {
        Write-Host "[提示] $task 不存在或已停用（可忽略）" -ForegroundColor Yellow
    }
}

# ---- 2. 停服务 + 改为手动启动 ----
foreach ($svc in @($KeilServiceName, $TunnelServiceName)) {
    $code = Invoke-Nssm @("set", $svc, "Start", "SERVICE_DEMAND_START")
    if ($code -eq 0) {
        Write-Host "[OK] $svc 启动类型已改为手动（不再开机自启）" -ForegroundColor Green
    } else {
        Write-Host "[警告] 修改 $svc 启动类型失败（退出码 $code）" -ForegroundColor Yellow
    }
    $code = Invoke-Nssm @("stop", $svc)
    if ($code -eq 0) {
        Write-Host "[OK] $svc 已停止" -ForegroundColor Green
    } else {
        Write-Host "[警告] $svc 停止失败（退出码 $code）" -ForegroundColor Yellow
    }
}

# ---- 3. 验证 ----
Start-Sleep -Seconds 1
$allStopped = $true
foreach ($svcName in @($KeilServiceName, $TunnelServiceName)) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "     $svcName = $($svc.Status)（启动类型：$($svc.StartType)）" -ForegroundColor Cyan
        if ($svc.Status -ne "Stopped") { $allStopped = $false }
    }
}

if ($allStopped) {
    Write-Host ""
    Write-Host "[完成] 编译服务器已停止，开机不再自启" -ForegroundColor Green
    Write-Host "       恢复：管理员运行 .\keil_server\deploy\start_server.ps1" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "[警告] 仍有服务未完全停止，请检查上方状态" -ForegroundColor Yellow
}
