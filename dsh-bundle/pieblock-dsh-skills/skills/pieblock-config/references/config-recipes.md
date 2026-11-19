# 构型配方与参数规则

本文件是 `pieblock-config` Skill 的配方库。示例工程在本 Skill 的 `assets/examples/`，公式与能力边界来自教材与示例；
引用位置写在各节末尾。**示例工程的轮位标签、转向增益与 RX 极性约定并不完全统一**，照抄前
先读本文件末尾的「符号与轮位」一节。

## 1. 能力矩阵（先确认做不做得到）

| 构型 | 工程类型 | 执行器 | 本期结论 | 参考 |
| --- | --- | --- | --- | --- |
| 差速四轮 | 步兵 / 工程 | 4 电机 P74–P77 | 内建底盘，支持（`chassis.enabled=true`） | 应用内模板 |
| 四轮麦轮（预制底盘） | 步兵必须；工程可选 | 4 电机 | 支持，最简单 | 应用内模板（步兵） |
| 四轮麦轮（关底盘 + 表达式） | 工程 | 4 电机 | 支持，有示例 | `assets/examples/mecanum4.pieproj` |
| 三轮全向（关底盘 + 表达式） | 工程 | 3 电机 P74–P76 | 支持，有示例 | `assets/examples/omni3.pieproj` |
| 四轮全向（关底盘 + 表达式） | 工程 | 4 电机 P74–P77 | 表达式可写，无官方示例，必须台架验证 | 教材公式见 §5 |
| 2-DOF 机械臂 | 工程（底盘关闭） | 2 舵机 MP03/MP74 | 支持，有示例 | `assets/examples/arm2dof.pieproj` |
| 3-DOF 机械臂 | 工程 | MP03/MP74 + P60 | 有条件（局部坐标、PWMA 50 Hz） | 教材第 5 章 |
| 四轮麦轮 + 2-DOF 臂 | 工程 | P74–P77 + MP03/MP74 | 支持，单模式约 16 行 | 教材第 5 章 |
| 舵轮四模块 | — | 4 电机 + 4 舵机 | 无内建、表达式手工可拼但**不推荐**、无示例 | 不接 |
| 6-DOF / 数值 IK | — | — | **不支持** | 不接 |
| 调试 / 音乐 | debug / music | 蜂鸣器/OLED | 支持 | `assets/examples/debug-checklist.pieproj`、`music-twinkle.pieproj` |

出处：教材第 5 章「构型能力矩阵」（仓库 `book/chapters/ch05.tex`，无源码时按 tag 读 GitHub）。

## 2. 基线怎么选

| 用户意图 | 基线 | 要改什么 |
| --- | --- | --- |
| 标准四轮麦轮 | 步兵用模板的预制底盘；工程可保持/开启 `chassis.enabled` | 四轮 IO、方向、通道、速度 |
| 四轮麦轮混控/教学 | `assets/examples/mecanum4.pieproj`（工程，关底盘） | 通道、引脚、按键；需要转向时加 RX 项 |
| 三轮全向 | `assets/examples/omni3.pieproj`（工程，关底盘） | 通道、引脚；需要转向时加 RX 项或按 §5 公式 |
| 四轮全向 | 无示例；从 `omni3` 或 `mecanum4` 复制后按 §5 公式改 4 行 | 全部轮速表达式 |
| 二自由度臂 | `assets/examples/arm2dof.pieproj` | 舵机引脚、中位/限位、按键映射 |
| 发射机构 | 应用内模板（步兵） | `feeder_*`、`friction_*`、扳机键 |
| 调试/音乐 | 对应模板或示例 | 调试行/音符 |

规则：

- **改现有工程**：候选必须从用户当前 `.pieproj` 复制，只改需要项；拿示例整份替换会覆盖用户配置。
- **新/空工程**：可以从示例整份生成，但 `project_kind` 必须与用户工程一致。
- 示例优先用本地仓库副本；没有副本时按版本 tag 从 GitHub 取
  `https://raw.githubusercontent.com/louqingjie/PIE-Block/v1.8.0/assets/examples/<name>.pieproj`。

## 3. 项目类型与底盘开关

- `infantry`：`chassis.enabled` **必须为 `true`**，四轮 IO/方向/普通速度必填；适合标准四轮底盘。
  全向、机械臂等自定义混控用「工程」项目。
- `engineer`：`chassis.enabled` 可为 `false`。关闭后四轮字段可为 `null`，P74–P77 释放给
  动作行；`preserve_chassis` 决定模式切换时是否保留底盘输出。
- 预制底盘 JSON（步兵模板，实车方向需台架确认）：

```json
"chassis": {
  "enabled": true,
  "left_front":  {"pin": "P74 P24", "direction": "forward"},
  "left_rear":   {"pin": "P75 P25", "direction": "forward"},
  "right_front": {"pin": "P76 P26", "direction": "reverse"},
  "right_rear":  {"pin": "P77 P27", "direction": "reverse"},
  "normal_speed": 6000,
  "sprint_speed": null,
  "sprint_enabled": false,
  "turn_reversed": false,
  "turn_sensitivity": 100
}
```

## 4. 引脚、PWM 与角色

| 角色（JSON 值） | 可用引脚 | 频率要求 |
| --- | --- | --- |
| `motor`（平滑电机） | P60、P62、P74–P77 | 所在组 10000 Hz（工程可设 50 Hz 但只建议舵机/摩擦轮用 50） |
| `jitterMotor`（抖动电机） | 同 `motor` | 同上 |
| `servo` / `friction` | 8 个扩展脚 + MP03/MP74 | 该组 50 Hz |
| `unused` | 全部输出脚 | — |

- 分组：PWMA、PWMB 两组共享频率；步兵 PWMA 固定 50 Hz、PWMB 固定 10000 Hz；工程两组可选。
- P64、P66 **不能**设为电机；P74–P77 要接舵机/摩擦轮时把该组改 50 Hz。
- MP74 与扩展板 P74 不是同一个 IO；MP03/MP74 只能舵机/摩擦轮。
- 同一引脚只能一个角色；动作行引用的引脚必须角色匹配。
- 角色写英文稳定值，不要写中文。

## 5. 轮速公式（教材，供推导；实车必须台架验证）

记号：`Vx` 前进为正，`Vy` 左移为正，`ω` 左转为正；摇杆输入 `前进 = -LY`、`左移 = LX`、
`转向增益 = 0.5*RX`（示例值，可调；RX 极性反了就把转向项整体取反）。duty 统一用
`*10000/2047`，生成器会自动钳位到 ±10000。

### 四轮麦轮（教材式）

```text
v_FL = Vx - Vy - kω
v_FR = Vx + Vy + kω
v_RL = Vx + Vy - kω
v_RR = Vx - Vy + kω
```

其中 k 为 `(L+W)/2` 或示例增益 0.5。直接写成动作行（教材简明版表，P74 左前、P75 右前、
P76 左后、P77 右后）：

```text
P74: (-LY-LX+0.5*RX)*10000/2047
P75: (-LY+LX-0.5*RX)*10000/2047
P76: (-LY+LX+0.5*RX)*10000/2047
P77: (-LY-LX-0.5*RX)*10000/2047
```

### 三轮全向（轮心 30°/150°/270°）

```text
v1 = -0.5Vx + 0.866Vy + Rω
v2 = -0.5Vx - 0.866Vy + Rω
v3 = Vx + Rω
```

直接写成动作行（教材简明版表）：

```text
P74: (0.5*LY+0.866*LX-0.5*RX)*10000/2047
P75: (0.5*LY-0.866*LX-0.5*RX)*10000/2047
P76: (-LY-0.5*RX)*10000/2047
```

### 三轮全向（`omni3.pieproj` 的 0°/120°/240° 布局，无转向）

```text
P74: vx*10000/2047
P75: (-0.5*vx+0.866*vy)*10000/2047
P76: (-0.5*vx-0.866*vy)*10000/2047
```

### 四轮全向（轮心 45°/135°/225°/315°）

```text
v1 = -0.707Vx + 0.707Vy + Rω
v2 = -0.707Vx - 0.707Vy + Rω
v3 = +0.707Vx - 0.707Vy + Rω
v4 = +0.707Vx + 0.707Vy + Rω
```

直接写成动作行（教材简明版表）：

```text
P74: (0.707*LY+0.707*LX-0.5*RX)*10000/2047
P75: (0.707*LY-0.707*LX-0.5*RX)*10000/2047
P76: (-0.707*LY-0.707*LX-0.5*RX)*10000/2047
P77: (-0.707*LY+0.707*LX-0.5*RX)*10000/2047
```

> 四轮全向没有官方示例。先 `validate` + `codegen`，再让用户台架单轮点动确认每个轮子的
> 正方向与轮位；不要直接上车跑。

### 2-DOF 机械臂（`arm2dof.pieproj`）

- 工程、`chassis.enabled=false`、PWMA 50 Hz、MP03/MP74 为舵机；
- 用 `output_kind: "rational"` 的变量行做逆解，最后两行输出到舵机：
  `q1*180.0/PI`、`q2*180.0/PI-90.0`；
- 中位 `servo_mids`、限幅 `servo_min_limits` / `servo_max_limits` 必须按机构给值，
  第一次上电先小角度、慢速、支撑好机械臂；
- 表达式里可用 `abs/min/max/sign/sqrt/atan2`，常量 `PI`/`E`。

## 6. 发射机构与摩擦轮（步兵）

- 拨弹：`feeder_pin`（如 P60）、`feeder_direction`、`feed_mode`（如 `blockingOpenLoop`）、
  `trigger_key`、`trigger_speed`、`trigger_time_ms`；
- 摩擦轮：`friction_mode`、`friction_key/up/down`、`friction_p64_max_duty`、
  `friction_p66_max_duty`（500–800）、`friction_level_step`；
- 引脚角色与 PWM 组必须匹配（摩擦轮 → 50 Hz 组）。

## 7. 动作行与表达式

动作行字段：

```json
{
  "id": "唯一-id",
  "input_kind": "unspecified",
  "key": null,
  "output_kind": "pin",
  "pin": "P74",
  "variable": null,
  "expression": "(-LY-LX+0.5*RX)*10000/2047",
  "mode": null,
  "parameter": null
}
```

- `input_kind: "unspecified"` → 表达式行：`expression` 必填，`mode`/`parameter` 必须为空；
- `input_kind: "remote"` → 遥控映射行：`key` + `mode` + `parameter`，不能有 `expression`；
- `output_kind: "pin"` 直接写引脚；`"integer"` / `"rational"` 写变量（`variable` 必填）；
- 变量行必须先定义后引用（validate 会报未定义变量）；
- 变量名不能与内置输入、常量、函数、C 关键字重名；
- 表达式**不是 C 代码**：单条受限表达式，无分号、无语句、无自定义函数。

表达式内置输入：`LX LY RX RY`（轴，−2047..2047）、`UP DOWN LEFT RIGHT A B C D E LC RC`
（按键 0/1）；常量 `PI E`；函数 `abs min max sign sqrt atan2`（min/max 支持 2–64 个参数）。

## 8. 模式与按键

- `mode_count` 控制模式数；多模式需要 `switch_strategy`（`cycle` 循环 / `direct` 直选）
  与 `mode_switch_key` / `mode_keys`；
- 模式切换键不能与模式内动作键冲突，模式选择键不能重复（validate 会报）；
- 每个模式有 `preserve_chassis`（切换时是否保留底盘输出）与 `actions`；
- 组合构型（麦轮 + 机械臂）建议先做单模式，把 4 行轮速 + 舵机行动作放进同一个模式。

## 9. 符号与轮位（务必人工确认）

- 教材例子的轮位标签、坐标系与转向极性不完全一致：`mecanum4.pieproj` / `omni3.pieproj`
  只含平移分量，且示例以**右方为 +y**；教材简明版的直接表达式以**左方为 +y**。不要混用。
- 三轮全向示例是 0°/120°/240° 布局，教材公式是 30°/150°/270° 布局，表达式不同。
- 因此：**轮位→引脚的对应关系必须由用户确认**（台架单轮点动），AI 只按用户确认的对应关系
  填表达式；表达式里某个轮子方向反了，整体取反该行即可，不必改接线。

## 10. validate 常见错误

| 报错 | 处理 |
| --- | --- |
| 引脚角色与 PWM/能力不匹配 | 按 §4 改角色或该组频率 |
| 引脚已被占用 / 同一引脚下多种角色 | 调整角色或改到空闲脚 |
| 表达式编译错误 | 按 `issues[].message` 修语法/类型，不能带分号或多条语句 |
| 未定义变量 | 变量行放到引用之前 |
| 必填项缺失 | 按教材补通道/死区/IO/方向/速度 |
| 步兵底盘必须启用 | 步兵不能关底盘；自定义混控改用「工程」项目 |

## 参考

- 能力矩阵与构型说明：教材第 5 章（仓库 `book/chapters/ch05.tex`，无源码时按 tag 读 GitHub）
- 示例工程：`assets/examples/`
- 字段语义与格式：`assets/docs/Flutter项目文件格式.md`
- 硬件约束：`assets/docs/STC32G固件约束.md`
- 表达式实现：按 tag 读 GitHub `packages/pieblock_core/lib/src/expression.dart`
