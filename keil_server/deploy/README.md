# deploy/ — 服务器部署与运维脚本

把编译服务器从「手动开个窗口跑」升级为「Windows 服务 + 自动监控」，共 6 个脚本：

| 脚本 | 作用 |
|---|---|
| `install_nssm.ps1` | **一键托管**：把 keil_server（PieBlockKeil）和 cloudflared 隧道（PieBlockTunnel）装成 NSSM 服务：崩溃自动重启、开机自启、日志落盘与 1MB 轮转、SYSTEM 账号环境变量固化（KEIL_API_KEY / KEIL_PATH）。可重复运行（幂等） |
| `uninstall_nssm.ps1` | 停止并删除上述两个服务（`-AlsoRemoveTasks` 连计划任务一起删） |
| `install_scheduled_tasks.ps1` | 注册两个计划任务：健康监控（每 60 秒，任务计划程序最小间隔 1 分钟）+ 每日备份（03:00） |
| `stop_server.ps1` / `start_server.ps1` | 停用/恢复整个编译服务（不删服务）：停止服务 + 改手动启动 + 停/启健康监控任务 |
| `monitor_health.ps1` | 健康检查：`/health` 连续失败 3 次自动重启服务；检查隧道服务存活；可选公网全链路探测（需 `-PublicUrl`） |
| `backup_data.ps1` | 每日备份不可再生数据：`api_keys.json`（用户 key 表）、`admin_key.txt`、隧道配置与凭证 json、环境快照；默认保留 14 天 |
| `start_public.ps1` | （原有）前台一键启动，未托管时的临时方案 |

## 上机三步走（管理员 PowerShell）

```powershell
# 1. 进程托管（需先下载 NSSM 到 C:\nssm\nssm.exe）
.\keil_server\deploy\install_nssm.ps1

# 2. 自动化（健康监控 + 每日备份）
.\keil_server\deploy\install_scheduled_tasks.ps1 -PublicUrl "https://build.pieblock.asia/health"

# 3. 验证
Get-Service PieBlockKeil, PieBlockTunnel              # 均 Running
curl http://127.0.0.1:8000/health                     # status: ok
Get-ScheduledTaskInfo -TaskName PieBlockHealthMonitor # LastRunTime 应为最近
```

## 常用命令

```powershell
# 查看监控日志（自动重启都会有记录）
Get-Content keil_server\data\logs\monitor.log -Tail 20

# 手动重启编译服务
Restart-Service PieBlockKeil -Force

# 升级代码后重启服务（进行中的编译任务会标 failed，客户端需重试）
nssm restart PieBlockKeil

# 全量卸载（服务 + 计划任务）
.\keil_server\deploy\uninstall_nssm.ps1 -AlsoRemoveTasks
```

## 设计说明

- **环境变量为什么在脚本里写死**：NSSM 服务以 SYSTEM 账号运行，读不到你登录用户的
  `KEIL_API_KEY` / `KEIL_PATH`，所以安装时必须显式写入服务（`AppEnvironmentExtra`）。
- **监控为什么用计划任务而不是 NSSM 内嵌**：NSSM 只管"进程死没死"，卡死/Keil 丢失
  它不知道；30 秒一次的 `/health` 探测能发现"进程活着但服务不可用"。
- **重启防抖**：`monitor_health.ps1` 两次重启至少间隔 60 秒，避免服务起不来时
  每 30 秒重启一次打循环。
- **备份目标**：默认 `C:\pieblock-backup`（计划任务以最高权限运行，可写系统盘根）。
  恢复到新机器 = 把 `api_keys.json` / `admin_key.txt` 复制回 `keil_server\data\`，
  隧道配置与凭证复制回原位置。注意 Keil 许可证机器绑定，换机要重新申请。
