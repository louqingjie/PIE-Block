# 卸载 NSSM 服务（PieBlockKeil 编译服务 + PieBlockTunnel 公网隧道）。
#
# 用法（管理员 PowerShell）：
#   .\keil_server\deploy\uninstall_nssm.ps1
#   .\keil_server\deploy\uninstall_nssm.ps1 -AlsoRemoveTasks   # 连计划任务一起删
#
# 可选参数：
#   -NssmExe          NSSM 路径（默认 C:\nssm\nssm.exe）
#   -AlsoRemoveTasks  同时删除健康监控与每日备份计划任务

param(
    [string]$NssmExe = "C:\nssm\nssm.exe",
    [switch]$AlsoRemoveTasks
)

$ErrorActionPreference = "Stop"
$KeilServiceName = "PieBlockKeil"
$TunnelServiceName = "PieBlockTunnel"

# 同 install_nssm.ps1：PS 5.1 下 EAP=Stop 时原生命令的 stderr 会抛终止错误，
# 统一用 $LASTEXITCODE 判断真实成败
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

if (-not (Test-Path $NssmExe)) {
    Write-Host "[错误] 找不到 NSSM：$NssmExe" -ForegroundColor Red
    exit 1
}

foreach ($svc in @($KeilServiceName, $TunnelServiceName)) {
    Write-Host "[1/2] 停止并删除服务 $svc ..." -ForegroundColor Cyan
    $null = Invoke-Nssm @("stop", $svc)
    $code = Invoke-Nssm @("remove", $svc, "confirm")
    if ($code -eq 0) {
        Write-Host "[OK] $svc 已删除" -ForegroundColor Green
    } else {
        Write-Host "[提示] $svc 不存在或已删除（可忽略）" -ForegroundColor Yellow
    }
}

if ($AlsoRemoveTasks) {
    Write-Host "[2/2] 删除计划任务 ..." -ForegroundColor Cyan
    foreach ($task in @("PieBlockHealthMonitor", "PieBlockDailyBackup")) {
        try {
            Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
            Write-Host "[OK] $task 已删除" -ForegroundColor Green
        } catch {
            Write-Host "[提示] $task 不存在（可忽略）" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[提示] 计划任务未删除。如需一并删除：uninstall_nssm.ps1 -AlsoRemoveTasks" -ForegroundColor Yellow
}

Write-Host "[完成] 服务与文件目录未改动（data/、.venv、Keil 等保留）" -ForegroundColor Green
