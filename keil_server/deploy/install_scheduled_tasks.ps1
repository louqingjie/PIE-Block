# 注册两个计划任务：
#   1. PieBlockHealthMonitor — 每 30 秒跑 monitor_health.ps1，服务挂了自动重启
#   2. PieBlockDailyBackup  — 每天 03:00 跑 backup_data.ps1，备份 key 表与凭证
#
# 前提：已先运行 install_nssm.ps1 装好 NSSM 服务。
# 用法（管理员 PowerShell）：
#   .\keil_server\deploy\install_scheduled_tasks.ps1
#   .\keil_server\deploy\install_scheduled_tasks.ps1 -PublicUrl "https://build.pieblock.asia/health"
#   .\keil_server\deploy\install_scheduled_tasks.ps1 -SkipBackup -MonitorIntervalSeconds 60
#
# 可选参数：
#   -MonitorIntervalSeconds  健康检查间隔，最小 60（任务计划程序限制，默认 60）
#   -BackupTime              每日备份时间（默认 03:00）
#   -PublicUrl               公网地址，提供时监控也会探测公网并重启隧道
#   -SkipMonitor / -SkipBackup   跳过对应任务

param(
    [int]$MonitorIntervalSeconds = 60,
    [string]$BackupTime = "03:00",
    [string]$PublicUrl = "",
    [switch]$SkipMonitor,
    [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"

# 任务计划程序最小重复间隔为 1 分钟（PT1M），小于 60 会报 0x80041318
if ($MonitorIntervalSeconds -lt 60) {
    Write-Host "[提示] 重复间隔最小 1 分钟，已将 ${MonitorIntervalSeconds}s 调整为 60s" -ForegroundColor Yellow
    $MonitorIntervalSeconds = 60
}

$monitorPs1 = Join-Path $PSScriptRoot "monitor_health.ps1"
$backupPs1 = Join-Path $PSScriptRoot "backup_data.ps1"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$py = Join-Path $root ".venv\Scripts\python.exe"

if (-not (Test-Path $py)) {
    Write-Host "[错误] 找不到 $py，请先创建 .venv" -ForegroundColor Red
    exit 1
}

# 以 SYSTEM 账户运行（服务账户，会话 0 无桌面）：
#   1) 不弹任何窗口——Interactive+Highest 的任务每次触发会在桌面闪 PowerShell 窗口，打扰日常使用
#   2) 权限足够（Restart-Service 等正常），无需 UAC
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

if (-not $SkipMonitor) {
    Write-Host "[1/2] 注册健康监控任务（每 ${MonitorIntervalSeconds} 秒）..." -ForegroundColor Cyan
    $monitorArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitorPs1`""
    if ($PublicUrl) { $monitorArgs += " -PublicUrl `"$PublicUrl`"" }
    $actionM = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $monitorArgs
    $triggerM = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $MonitorIntervalSeconds)
    $settingsM = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Seconds 60)
    try {
        Register-ScheduledTask -TaskName "PieBlockHealthMonitor" -Action $actionM -Trigger $triggerM `
            -Settings $settingsM -Principal $principal -Description "Keil 编译服务健康检查，连续失败自动重启（NSSM）" -Force -ErrorAction Stop | Out-Null
        Write-Host "[OK] PieBlockHealthMonitor 已注册（每 $MonitorIntervalSeconds 秒）" -ForegroundColor Green
    } catch {
        Write-Host "[错误] PieBlockHealthMonitor 注册失败：$($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if (-not $SkipBackup) {
    Write-Host "[2/2] 注册每日备份任务（每天 $BackupTime）..." -ForegroundColor Cyan
    $backupArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$backupPs1`""
    $actionB = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $backupArgs
    $triggerB = New-ScheduledTaskTrigger -Daily -At $BackupTime
    $settingsB = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    try {
        Register-ScheduledTask -TaskName "PieBlockDailyBackup" -Action $actionB -Trigger $triggerB `
            -Settings $settingsB -Principal $principal -Description "每日备份 Keil 编译服务配置（key 表/凭证）" -Force -ErrorAction Stop | Out-Null
        Write-Host "[OK] PieBlockDailyBackup 已注册（每天 $BackupTime）" -ForegroundColor Green
    } catch {
        Write-Host "[错误] PieBlockDailyBackup 注册失败：$($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " 计划任务已就绪。查看运行情况：" -ForegroundColor Green
Write-Host "   Get-ScheduledTask -TaskName PieBlock* " -ForegroundColor Cyan
Write-Host "   Get-ScheduledTaskInfo -TaskName PieBlockHealthMonitor" -ForegroundColor Cyan
Write-Host " 监控日志：$root\keil_server\data\logs\monitor.log" -ForegroundColor Green
Write-Host " 删除：uninstall_nssm.ps1 -AlsoRemoveTasks" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
