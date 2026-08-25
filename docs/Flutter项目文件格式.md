# Flutter 项目文件格式

`.pieproj` 是 UTF-8 JSON 文件。格式 14 使用稳定语义字段，不包含 UI 控件路径或生成代码，并保存可恢复的向导进度。

```json
{
  "format_version": 14,
  "name": "我的机器人",
  "project_kind": "infantry",
  "created_at": "2026-08-25T01:00:00.000Z",
  "updated_at": "2026-08-25T01:05:00.000Z",
  "guide_progress": {
    "current_step_id": "mechanism",
    "visited_step_ids": ["remote", "mechanism"]
  },
  "config": {
    "remote": {"channel": null, "deadzone": null},
    "chassis": {},
    "feeder_pin": null,
    "yaw": {"drive": null, "pin": null},
    "pitch": {"drive": null, "pin": null},
    "friction_mode": null,
    "buzzer_disabled": false
  }
}
```

`project_kind` 仅支持 `infantry` 与 `engineer`。枚举保存稳定英文值，中文只用于界面展示。

`current_step_id` 和 `visited_step_ids` 使用稳定步骤 ID；重开项目后恢复离开时的页面和已访问范围。步骤变化与配置变化使用同一自动保存流程。

新项目的必填数值、枚举、按键、IO、方向、驱动类型、工程 PWM 和模式策略均为 `null`，应用不会替用户提前选择。纯可选开关默认关闭。

步兵配置不保存 `pwm`：PWMA 固定为 50Hz，PWMB 固定为 10000Hz，其他引脚角色由实际选择自动推导。只有 `friction_mode` 为 `brushlessEsc` 时 P64/P66 才固定用于摩擦轮；选择 `disabled` 时两端口释放。工程配置继续保存 `pwm`，允许配置分组频率、引脚角色和舵机中位。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。应用使用同目录临时文件写入后替换目标文件。

格式 13 及其他版本均不兼容格式 14。应用会拒绝打开并提示在对应旧版 PIE-Block 中处理，不执行自动转换。
