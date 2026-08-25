# Flutter 项目文件格式

`.pieproj` 是 UTF-8 JSON 文件。格式 12 使用稳定语义字段，不包含 UI 控件路径、生成代码或工作流状态。

```json
{
  "format_version": 12,
  "name": "我的机器人",
  "project_kind": "infantry",
  "created_at": "2026-08-25T01:00:00.000Z",
  "updated_at": "2026-08-25T01:05:00.000Z",
  "config": {
    "remote": {"channel": 36, "deadzone": 10},
    "chassis": {},
    "pwm": {}
  }
}
```

`project_kind` 仅支持 `infantry` 与 `engineer`。枚举在文件中保存稳定英文值，中文只用于界面展示。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。

应用使用同目录临时文件写入后替换目标文件。无法写入时顶部状态会显示“保存失败”，项目仍留在内存中。

格式 11 及更早版本基于 Godot 节点路径，与格式 12 不兼容。新版遇到其他版本会拒绝打开并给出明确提示。
