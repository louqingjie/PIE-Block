# 每日备份脚本：备份不可再生的配置（用户 key 表、管理员 key、隧道配置与凭证），
# 并留一份环境快照，便于故障后恢复或迁移服务器。
# 备份目标默认 C:\pieblock-backup（系统盘根目录，计划任务以最高权限运行）。
#
# 由 install_scheduled_tasks.ps1 注册为计划任务 PieBlockDailyBackup，
# 也可手动运行：
#   .\keil_server\deploy\backup_data.ps1
#   .\keil_server\deploy\backup_data.ps1 -Dest "D:\backup" -KeepDays 7
#
# 可选参数：
#   -Dest      备份根目录（默认 C:\pieblock-backup）
#   -KeepDays  保留天数，超出删除（默认 14）

param(
    [string]$Dest = "C:\pieblock-backup",
    [int]$KeepDays = 14
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataDir = Join-Path $root "keil_server\data"
$deployDir = $PSScriptRoot

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $Dest $stamp
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Write-Host "[OK] 备份目录：$backupDir" -ForegroundColor Green

# ---- 1. 用户 key 表 + 管理员 key（丢了要重发全队 key） ----
foreach ($f in @("api_keys.json", "admin_key.txt")) {
    $src = Join-Path $dataDir $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $backupDir $f)
        Write-Host "[OK] 已备份 $f" -ForegroundColor Green
    } else {
        Write-Host "[提示] 无 $f（尚未生成？可忽略）" -ForegroundColor Yellow
    }
}

# ---- 2. 隧道配置 + 凭证（凭证 json 由 cloudflared login 生成，删了要重新授权） ----
$tunnelCfg = Join-Path $deployDir "cloudflared-config.yml"
if (Test-Path $tunnelCfg) {
    Copy-Item $tunnelCfg (Join-Path $backupDir "cloudflared-config.yml")
    Write-Host "[OK] 已备份隧道配置" -ForegroundColor Green
    $cfgText = Get-Content $tunnelCfg -Raw
    $m = [regex]::Match($cfgText, "(?m)^\s*credentials-file:\s*(.+?)\s*$")
    if ($m.Success) {
        $credPath = $m.Groups[1].Value.Trim().Trim('"')
        if (Test-Path $credPath) {
            Copy-Item $credPath (Join-Path $backupDir "tunnel-credentials.json")
            Write-Host "[OK] 已备份隧道凭证" -ForegroundColor Green
        } else {
            Write-Host "[警告] 凭证文件不存在：$credPath" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[提示] 无隧道配置（未部署公网？可忽略）" -ForegroundColor Yellow
}

# ---- 3. 环境快照（服务状态 + 版本），便于对照排查 ----
$snapshot = @()
$snapshot += "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$snapshot += "系统: $($env:OS) / $((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption)"
$snapshot += ""
$snapshot += "--- 服务状态 ---"
foreach ($svcName in @("PieBlockKeil", "PieBlockTunnel")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $snapshot += "$svcName = $($svc.Status)（启动类型：$($svc.StartType)）"
    } else {
        $snapshot += "$svcName = 未安装"
    }
}
$snapshot += ""
$snapshot += "--- Python / 依赖 ---"
$py = Join-Path $root ".venv\Scripts\python.exe"
if (Test-Path $py) {
    $snapshot += (& $py --version).ToString()
    try {
        $snapshot += (& $py -m pip freeze 2>$null | Out-String)
    } catch {
        $snapshot += "（pip freeze 失败：$($_.Exception.Message)）"
    }
}
$snapshot | Set-Content -Path (Join-Path $backupDir "环境快照.txt") -Encoding UTF8
Write-Host "[OK] 已生成环境快照" -ForegroundColor Green

# ---- 4. 清理过期备份 ----
$cutoff = (Get-Date).AddDays(-$KeepDays)
$removed = 0
Get-ChildItem $Dest -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt $cutoff -and $_.Name -match "^\d{8}_\d{6}$"
} | ForEach-Object {
    Remove-Item $_.FullName -Recurse -Force
    $removed++
}
if ($removed -gt 0) { Write-Host "[OK] 已清理 $removed 个过期备份（> $KeepDays 天）" -ForegroundColor Green }

Write-Host "[完成] 备份完成：$backupDir" -ForegroundColor Green
Write-Host "       恢复方法：把 api_keys.json / admin_key.txt 复制回 $dataDir，" -ForegroundColor Cyan
Write-Host "       cloudflared-config.yml 与凭证复制回对应原位置即可" -ForegroundColor Cyan
