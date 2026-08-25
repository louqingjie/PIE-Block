# Flutter 项目文件格式

`.pieproj` 是 UTF-8 JSON 文件。格式 13 使用稳定语义字段，不包含 UI 控件路径、生成代码或向导状态。

```json
{
  "format_version": 13,
  "name": "我的机器人",
  "project_kind": "infantry",
  "created_at": "2026-08-25T01:00:00.000Z",
  "updated_at": "2026-08-25T01:05:00.000Z",
  "config": {
    "remote": {"channel": 36, "deadzone": 10},
    "chassis": {},
    "feeder_pin": "P60",
    "yaw": {"drive": "servo", "pin": "MP74"},
    "pitch": {"drive": "servo", "pin": "MP03"},
    "buzzer_disabled": false
  }
}
```

`project_kind` 仅支持 `infantry` 与 `engineer`。枚举保存稳定英文值，中文只用于界面展示。

步兵配置不保存 `pwm`：PWMA 固定为 50Hz，PWMB 固定为 10000Hz，P64/P66 固定用于摩擦轮，其他引脚角色由底盘、拨弹和云台配置自动推导。工程配置继续保存 `pwm`，允许配置分组频率、引脚角色和舵机中位。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。应用使用同目录临时文件写入后替换目标文件。

格式 12 及其他版本均不兼容格式 13。应用会拒绝打开并提示在对应旧版 PIE-Block 中处理，不执行自动转换。
