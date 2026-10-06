# Flutter 项目文件格式

`.pieproj` 是 UTF-8 JSON 文件。格式 16 使用稳定语义字段，不包含 UI 控件路径或生成代码，并保存可恢复的向导进度。

```json
{
  "format_version": 16,
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
    "chassis": {"turn_reversed": false},
    "feeder_pin": null,
    "yaw": [{"drive": null, "pin": null}],
    "pitch": [{"drive": null, "pin": null}],
    "friction_mode": null,
    "friction_p64_max_duty": null,
    "friction_p66_max_duty": null,
    "friction_level_step": null,
    "buzzer_disabled": false
  }
}
```

`project_kind` 支持 `infantry`、`engineer`、`debug` 与 `music`。枚举保存稳定英文值，中文只用于界面展示。

`current_step_id` 和 `visited_step_ids` 使用稳定步骤 ID；重开项目后恢复离开时的页面和已访问范围。步骤变化与配置变化使用同一自动保存流程。

步兵和工程向导的最后一步稳定 ID 均为 `deploy`，用于“编译与烧录”页。新增该步骤不改变项目格式版本。

新项目的必填数值、枚举、按键、IO、方向、驱动类型、工程 PWM 和模式策略均为 `null`，应用不会替用户提前选择。纯可选开关默认关闭。

步兵和工程项目的 `chassis.turn_reversed` 是共用底盘校准项，默认 `false`；启用后仅反转水平摇杆及左右方向键产生的转向量，不改变直行、倒车、冲刺或单轮方向配置。

工程动作的 `mode` 支持 `direct`、`incremental`、`speed`、`accelerate`、`single` 和 `continuous`。数字按键控制舵机时可使用 `direct`（按键上升沿到达相对中位点的预设角度）、`single`（按键上升沿按灵敏度单次增加）或 `continuous`（按住期间按灵敏度逐主循环增加）。`direct` 的 `parameter` 为 0–90 的整数目标角度，方向决定中位点两侧；`single` 和 `continuous` 的 `parameter` 保存最多两位小数的角度灵敏度；其他动作参数仍为整数。

步兵配置不保存 `pwm`：PWMA 固定为 50Hz，PWMB 固定为 10000Hz，其他引脚角色由实际选择自动推导。只有 `friction_mode` 为 `brushlessEsc` 时 P64/P66 才固定用于摩擦轮；选择 `disabled` 时两端口释放。工程配置继续保存 `pwm`，允许配置分组频率、引脚角色和舵机中位。

步兵可选的 `reverse_feed_key` 保存反向拨弹键，`null` 表示不使用，生成的固件里也就没有反向拨弹逻辑。设置后按住该键期间拨弹电机按 `feeder_direction` 的反方向持续转动（速度复用 `trigger_speed`），松开立即归零；该键必须避让扳机键、摩擦轮按键以及已用于底盘的方向键。

步兵的 `yaw` 与 `pitch` 都是执行器数组。每个元素保存 `drive`、`pin`、`direction` 与舵机的 `mid_offset`；同一轴可以挂 1~N 个执行器，舵机与电机可混用且各自占用独立 IO、独立方向，空数组表示该轴不配置。所有执行器共享同一个摇杆通道（Yaw 用右摇杆水平、Pitch 用右摇杆垂直），生成固件时按数组顺序展开：每轴首个执行器沿用 `yawDuty`/`pitchDuty`，其余依次为 `yawDuty2`、`pitchDuty2`……

调试配置保存 `tests` 数组。数组始终包含 P60、P62、P64、P66、P74、P75、P76、P77、MP03、MP74 十个固定引脚，数组顺序就是固件执行顺序。每项保存 `enabled`、`drive_type`、`direction`、`value`；电机和舵机额外保存 `duration_ms`。摩擦轮仅限 P64/P66，`value` 表示 0–100 的油门百分比，曲线按 20% 一档爬升再回落、每档固定 1.5 秒，最后补一档 0 表示停机；与运行控制共用同一条映射律，见下节。

音乐配置保存 `ticks_per_quarter`、`source_name`、`track_name`、`notes`、`tempo_events` 和 `time_signature_events`。每个音符保存稳定 `id`、`pitch`、`start_tick`、`duration_ticks` 与 `primary`；相同起始 tick 必须且只能有一个主音，其他音符作为低亮度参考并参与 MIDI 导出。速度事件保存每四分音符微秒数，拍号事件保存分子和分母，两类事件都从 tick 0 开始并严格递增。项目不保存原始 MIDI 字节、力度、乐器、通道或控制器。

## 摩擦轮的比例值控制

摩擦轮以**油门比例值**为唯一控制量，不再直接控制占空比真值。两个摩擦轮按引脚分别配置满油占空比，用来补偿两侧机械差异导致的转速差；引脚是唯一真相源，配置里不引入左右侧概念。

映射律：

```
duty(引脚) = 500 + 油门% × (该引脚满油上限 − 500) ÷ 100
```

`500` 是电调启动信号，固定不可调，同时作为映射下界。步兵配置用 `friction_p64_max_duty` 与 `friction_p66_max_duty` 保存两个满油上限（500–800 的整百值），`friction_level_step` 保存每次按键的油门步长百分比（1–100）。调试配置同样保存这两个上限，只有当某个引脚确实被用作摩擦轮时才要求填写对应上限。

例如 P64 上限 700、P66 上限 800 时，油门 0% 得 `500 / 500`，50% 得 `600 / 650`，100% 得 `700 / 800`。

按键只改油门百分比，两侧目标占空比每个主循环由油门重新映射。平滑渐变跑在占空比上，两侧各自以 ±1 duty/周期逼近自己那侧的目标，因此 duty 变化率不超过 50/s，满足《RM电控指南》的 ≤100 duty/s 上限。启停时仍跳过 0~500 的无效区间：输出只取 0 或 500~各自上限。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。HEX、编译日志、编译器选择和 Keil 路径也不写入 `.pieproj`：构建产物放在用户本地缓存，编译器偏好属于应用设置。应用使用同目录临时文件写入后替换目标文件。

格式 15 及其他版本均不兼容格式 16。应用会拒绝打开并提示在对应旧版 PIE-Block 中处理，不执行自动转换。
