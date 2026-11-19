# 参数 ↔ 生成代码对照手册

本手册用于把 `.pieproj` 里的参数值落到生成的 `main.c` 上，逐项核对。锚点基于 PIE-Block 1.8.x
（格式 23）核实；**生成器实现不是公开 ABI**，大版本之间可能调整，换版本后要重新对照。

## 0. 前提与版本

- 用 `pieblock-cli describe` 确认 CLI 版本，与 PIE-Block 版本一致；
- 读源码按同一 tag（如 `v1.8.0`），链接形如
  `https://github.com/louqingjie/PIE-Block/blob/v1.8.0/<path>`；
- `codegen` 只接受 **0 error** 的工程；工程没配完时先 `validate`，不要拿旧缓存输出对照。

## 1. 三方对照（必要时四方）

```text
① 用户界面里填的值
        ▼（保存）
② .pieproj 存档值
        ▼（pieblock-cli codegen）
③ 规范生成代码
        ▲（用户从「生成代码」页导出）
④ 用户实际看到的 main.c
```

判断归属：

| 哪一环不一致 | 最可能的原因 |
| --- | --- |
| ① ≠ ② | 界面保存问题（或用户记错） |
| ② ≠ ③ | 生成器缺陷候选 |
| ③ ≠ ④ | 版本不同步、导出后被手改、构建缓存 |
| 全都一致但行为不对 | 参数语义/硬件/接线/烧录/操作 |

`③` 与 `④` 的比对很关键：两者理论上应完全一致（同一生成器、同一版本）。

## 2. 锚点表（1.8.x）

| `.pieproj` 参数 | 生成代码锚点 | 备注 |
| --- | --- | --- |
| `remote.channel` | `uint8_t Channal = <值>;` | 生成器里拼写就是 `Channal`，按此搜索 |
| `remote.deadzone` | `uint16_t deadBandOfLeft = ...;`、`deadBandOfRight` | 在 `ReadControllerInputs()` 里用于过滤摇杆 |
| `chassis.enabled` | 是否生成 `CalculateChassis()` 与 `dutyOfMotor[4..7]` 的底盘输出 | 关闭时不生成预制底盘逻辑 |
| `chassis.normal_speed` | `uint16_t maxSpeed = ...;` | `CalculateChassis()` 用它缩放摇杆 |
| `chassis.sprint_speed` | `uint16_t ultraSpeed = ...;` | 冲刺启用时参与加速/切换逻辑 |
| `chassis.*.direction` | 该轮 `dutyOfMotor` 的符号/方向帧位 | 具体取反位置以生成器实现为准 |
| `chassis.turn_reversed` / `turn_sensitivity` | `CalculateChassis()` 里转向分量的符号/缩放 | 格式 23 特性 |
| `feeder_pin` / `feeder_direction` | `ExpansionBoradControl(Dir_Change_Order, ..., dutyOfMotor[0/1] ...)` 与 `Duty_Change_Order` | P60/P62 对应 `dutyOfMotor[0]`、`[1]` |
| `trigger_key` / `trigger_speed` / `trigger_time_ms` | `RcKeyValueRead(KEY_OFFSET_*)` 与 `UpdateWeapons()` 里的拨弹触发 | 按键到 `KEY_OFFSET_n` 的映射由生成器决定，以生成结果为准 |
| `friction_*` | `FRICTION_MAX_DUTY_P64/P66`、`FRICTION_LEVEL_STEP`、`frictionDutyP64/66` | 摩擦轮专用 |
| 云台执行器 `mid_offset` / `min_limit` / `max_limit` | `PWM_Init(PWMB_CHx_..., 50, ...)`、`yawDuty`/`pitchDuty`、`417/1083` 限幅 | 舵机角度按相对中位偏移 |
| `mode_count` / `mode_switch_key` / `switch_strategy` | `currentMode`、`PrepareMode()`、`lastSwitch`、`modeKeyLast[]` | 工程/多模式工程 |
| 模式动作（表达式行） | **`/*@expr:modes.<模式>.<动作>.expression*/`** | 生成器直接把配置路径写进注释，最可靠 |
| 音乐工程音符 | `musicFrequencies[128]`、`MUSIC_*` 宏、五线谱数据表 | 乐谱会预计算成显示事件 |
| 调试工程行 | `CUE_*` 宏与测试序列 | 调试提示音方案 |
| 任何工程的引脚配置 | `ExpansionBoradControl(Init_Order, p60, p62, p64, p66, p74, p75, p76, p77)` | 21 字节帧，顺序固定 |
| `pwm.buzzer_disabled` | 是否生成 `UpdateBuzzerFeedback()` / 蜂鸣反馈代码 | 以生成结果为准 |

## 3. 怎么快速对照

```powershell
# 生成到临时目录（不要覆盖用户工程里的 main.c）
New-Item -ItemType Directory -Force "$env:TEMP\pb-check" | Out-Null
pieblock-cli codegen <工程.pieproj> > "$env:TEMP\pb-check\main.generated.c"

# 找常量
Select-String -Path "$env:TEMP\pb-check\main.generated.c" -Pattern "Channal|maxSpeed|ultraSpeed|deadBand"

# 找模式动作表达式（工程/多模式）
Select-String -Path "$env:TEMP\pb-check\main.generated.c" -Pattern "@expr:"
```

示例：`remote.channel` 从 36 改成 37 后，生成代码应只有一行相关变化：

```c
- uint8_t Channal = 36;
+ uint8_t Channal = 37;
```

如果代码没变：回到三方对照，先查存档是否真的保存了，再查版本与 `codegen` 输入路径是否搞错。

## 4. 生成代码的固定结构（便于定位）

- 文件头注释标明工程类型（步兵/工程/调试/音乐）与「由 PIE-Block 自动生成」；
- 常量区：`Channal`、`maxSpeed`、`ultraSpeed`、`deadBand*`、`FRICTION_*`、`MUSIC_*`、`CUE_*`；
- 通信：`ExpansionBoradControl()` 21 字节帧；
- 输入：`ReadControllerInputs()`；
- 底盘：`CalculateChassis()`（预制底盘时）；
- 模式：`PrepareMode()`、`RunMode1()`…（工程）；
- 武器：`UpdateWeapons()`（步兵）；
- 云台：`UpdateGimbal()`（步兵）；
- `main()` 里按顺序初始化、进主循环。

## 5. 源码位置（按 tag）

- 生成入口与各工程类型（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/code_generator.dart`
  （`CodeGenerator.generate`、`_infantry` / `_engineer` / `_music` / `_debug`）；
- 表达式编译（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/expression.dart`
  （`ExpressionParser`、`ExpressionEmitter`、`@expr` 标记）；
- 字段模型（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/models.dart`；
- 校验规则（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/validator.dart`；
- 生成结果缓存/构建：`software` 应用侧 `lib/src/deploy_controller.dart` 与 `pieblock_toolchain` 包。

## 6. 注意

- 生成器可能按配置**裁剪**代码（如 `buzzer_disabled`、`chassis.enabled=false`、未用到的 helper），
  「代码里没有某个函数」不一定代表 bug，先看参数；
- 音乐/调试工程的输出结构与步兵/工程差异很大，不要跨 kind 套锚点；
- 生成的 `main.c` 是只读产物：对照可以，修改不行；修复必须回到参数 + 生成器。
