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

`project_kind` 支持 `infantry`、`engineer`、`debug` 与 `music`。枚举保存稳定英文值，中文只用于界面展示。

`current_step_id` 和 `visited_step_ids` 使用稳定步骤 ID；重开项目后恢复离开时的页面和已访问范围。步骤变化与配置变化使用同一自动保存流程。

步兵和工程向导的最后一步稳定 ID 均为 `deploy`，用于“编译与烧录”页。新增该步骤不改变项目格式版本。

新项目的必填数值、枚举、按键、IO、方向、驱动类型、工程 PWM 和模式策略均为 `null`，应用不会替用户提前选择。纯可选开关默认关闭。

步兵配置不保存 `pwm`：PWMA 固定为 50Hz，PWMB 固定为 10000Hz，其他引脚角色由实际选择自动推导。只有 `friction_mode` 为 `brushlessEsc` 时 P64/P66 才固定用于摩擦轮；选择 `disabled` 时两端口释放。工程配置继续保存 `pwm`，允许配置分组频率、引脚角色和舵机中位。

调试配置保存 `tests` 数组。数组始终包含 P60、P62、P64、P66、P74、P75、P76、P77、MP03、MP74 十个固定引脚，数组顺序就是固件执行顺序。每项保存 `enabled`、`drive_type`、`direction`、`value`；电机和舵机额外保存 `duration_ms`。摩擦轮仅限 P64/P66，按固定 1.5 秒节拍从 500 渐变至 `value` 后归零。

音乐配置保存 `ticks_per_quarter`、`source_name`、`track_name`、`notes`、`tempo_events` 和 `time_signature_events`。每个音符保存稳定 `id`、`pitch`、`start_tick`、`duration_ticks` 与 `primary`；相同起始 tick 必须且只能有一个主音，其他音符作为低亮度参考并参与 MIDI 导出。速度事件保存每四分音符微秒数，拍号事件保存分子和分母，两类事件都从 tick 0 开始并严格递增。项目不保存原始 MIDI 字节、力度、乐器、通道或控制器。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。HEX、编译日志、编译器选择和 Keil 路径也不写入 `.pieproj`：构建产物放在用户本地缓存，编译器偏好属于应用设置。应用使用同目录临时文件写入后替换目标文件。

格式 13 及其他版本均不兼容格式 14。应用会拒绝打开并提示在对应旧版 PIE-Block 中处理，不执行自动转换。
