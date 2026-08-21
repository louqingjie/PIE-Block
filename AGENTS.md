请记得在合适时间提交Git并推送，提交信息需为中文，遵循 Conventional Commits
目前项目仍在快速迭代，还未正式发布，无需考虑向下兼容的问题

## Godot 无头测试

受限环境不能写入默认的 `%APPDATA%\\Godot` 和 `%LOCALAPPDATA%\\Godot`，会使 Godot Mono 在启动阶段崩溃。运行无头测试前，将这两个环境变量临时指向可写的临时目录；首次运行先执行一次导入：

```powershell
$root = Join-Path $env:TEMP "pie-block-godot-test"
New-Item -ItemType Directory -Force $root | Out-Null
$env:APPDATA = Join-Path $root "Roaming"
$env:LOCALAPPDATA = Join-Path $root "Local"
$godot = "C:\\Users\\louqi\\Desktop\\program\\Godot_v4.7.1-stable_mono_win64\\godot.exe"
& $godot --headless --path . --import --quit
& $godot --headless --path . --script res://scripts/test_project_file.gd
```

隔离环境可能提示“无法读取根证书库”；离线单元测试可忽略。需要联网的测试应在能访问真实用户配置目录的正常用户环境运行。
