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

步兵和工程向导的最后一步稳定 ID 均为 `deploy`，用于“烧录”页。新增该步骤不改变项目格式版本。

新项目的必填数值、枚举、按键、IO、方向、驱动类型、工程 PWM 和模式策略均为 `null`，应用不会替用户提前选择。纯可选开关默认关闭。

新建弹窗有一个默认关闭的「模板工程」开关。只有显式打开它时，配置才整份取自 `assets/templates/<kind>.pieproj`；项目文件本身不写入任何模板标记，创建出来就是普通项目，`name`、两个时间戳和 `guide_progress` 都按本次创建重新生成。模板文件同为 `format_version: 16`，格式版本变更时必须用 `dart run tool/generate_project_templates.dart` 重存四份模板，否则 `test/project_templates_test.dart` 会失败。步兵模板的拨弹电机落在固定 50Hz 的 PWMA（四轮已占满固定 10000Hz 的 PWMB），因此会带一条「电机可能一卡一卡」提示，这是既定取舍而非模板缺陷。

步兵和工程项目的 `chassis.turn_reversed` 是共用底盘校准项，默认 `false`；启用后仅反转水平摇杆及左右方向键产生的转向量，不改变直行、倒车、冲刺或单轮方向配置。

工程动作的 `mode` 支持 `direct`、`incremental`、`speed`、`accelerate`、`single` 和 `continuous`。数字按键控制舵机时可使用 `direct`（按键上升沿到达相对中位点的预设角度）、`single`（按键上升沿按灵敏度单次增加）或 `continuous`（按住期间按灵敏度逐主循环增加）。`direct` 的 `parameter` 为 0–90 的整数目标角度，方向决定中位点两侧；`single` 和 `continuous` 的 `parameter` 保存最多两位小数的角度灵敏度；其他动作参数仍为整数。

步兵配置不保存 `pwm`：PWMA 固定为 50Hz，PWMB 固定为 10000Hz，其他引脚角色由实际选择自动推导。只有 `friction_mode` 为 `brushlessEsc` 时 P64/P66 才固定用于摩擦轮；选择 `disabled` 时两端口释放。工程配置继续保存 `pwm`，允许配置分组频率、引脚角色和舵机中位。

调试配置保存 `tests` 数组。数组始终包含 P60、P62、P64、P66、P74、P75、P76、P77、MP03、MP74 十个固定引脚，数组顺序就是固件执行顺序。每项保存 `enabled`、`drive_type` 和 `value`；电机和舵机额外保存 `direction` 与 `duration_ms`，摩擦轮不保存方向与时长，测试期间也不发送方向帧。摩擦轮仅限 P64/P66：`value` 就是**目标占空比**本身（500–800，写成这张卡实测想跑的占空比），先给 `500` 启动占空比保持 1 秒完成电调激活，再逐周期平滑渐变到该目标，停留 1.5 秒后归零；低于 `600` 时只给一条提醒（可能带不动摩擦轮）。调试项目不再保存 `friction_*_max_duty`，也不再做「油门 → 满油上限」换算。

音乐配置保存 `ticks_per_quarter`、`source_name`、`track_name`、`notes`、`overlap_mode`、`new_note_interrupts`、`tempo_events` 和 `time_signature_events`。每个音符保存稳定 `id`、`pitch`、`start_tick` 和 `duration_ticks`，音符之间允许重叠。P33 蜂鸣器同时只能发一个音，因此按 `overlap_mode` 做单音裁决：`highest` 取高音、`lowest` 取低音、`nearest` 取最接近上一个有效发声音高的音符（曲首没有参照时取最高音）；`new_note_interrupts` 为真时后起始的音符会打断仍在发声的音符（被打断的尾巴不发声，卷帘里显示为灰色）。同一 tick 起始的一组音符按同一策略挑一个发声，其余整段不发声。不发声的音符/片段在卷帘里变灰，但数据仍完整保留并参与 MIDI 导出。速度事件保存每四分音符微秒数，拍号事件保存分子和分母，两类事件都从 tick 0 开始并严格递增。项目不保存原始 MIDI 字节、力度、乐器、通道或控制器。

## 摩擦轮的比例值控制

摩擦轮以**油门比例值**为唯一控制量，不再直接控制占空比真值。两个摩擦轮按引脚分别配置满油占空比，用来补偿两侧机械差异导致的转速差；引脚是唯一真相源，配置里不引入左右侧概念。

映射律：

```
duty(引脚) = 500 + 油门% × (该引脚满油上限 − 500) ÷ 100
```

`500` 是电调启动信号，固定不可调，同时作为映射下界。**步兵**配置用 `friction_p64_max_duty` 与 `friction_p66_max_duty` 保存两个满油上限（500–800 的整百值），`friction_level_step` 保存每次按键的油门步长百分比（1–100）。**调试**项目的摩擦轮测试项不走这套映射：测试项里的 `value` 直接就是目标占空比（500–800），低于 650 给提醒。

例如 P64 上限 700、P66 上限 800 时，油门 0% 得 `500 / 500`，50% 得 `600 / 650`，100% 得 `700 / 800`。

按键只改油门百分比，两侧目标占空比每个主循环由油门重新映射。平滑渐变跑在占空比上，两侧各自以 ±1 duty/周期逼近自己那侧的目标，因此 duty 变化率不超过 50/s，满足《RM电控指南》的 ≤100 duty/s 上限。启停时仍跳过 0~500 的无效区间：输出只取 0 或 500~各自上限。

摩擦轮从静止（占空比 0）启动时，两类工程都会先给 `500` 启动占空比并保持 **1000ms** 完成电调激活，再进入上面的斜坡；激活期间不驱动蜂鸣器反馈。步兵按主循环整圈折算这段保持时间（约 20ms 一圈，实际不短于 1000ms）；调试工程在摩擦轮测试项里直接 `Ms_Delay(1000)`。关闭摩擦轮时立即取消激活残留，直接走停机斜坡。

项目可以在配置未完成时保存。生成代码是配置的派生结果，不写入项目文件；任何配置变化都会重新检查并重新生成。HEX、编译日志、编译器选择和 Keil 路径也不写入 `.pieproj`：构建产物放在用户本地缓存，编译器偏好属于应用设置。应用使用同目录临时文件写入后替换目标文件。

格式 15 及其他版本均不兼容格式 16。应用会拒绝打开并提示在对应旧版 PIE-Block 中处理，不执行自动转换。
