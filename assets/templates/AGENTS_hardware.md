# STC32G 机器人固件开发约束

本工作区是 RoboMaster 机器人的单片机固件工程，程序默认用内置 **SDCC C251**
编译，也可在顶部下拉栏切换到 **Keil C251**。
**当前构型：{{KIND_LABEL}}。**
唯一需要修改的文件是 `{{MAIN_C_PATH}}`。

`Libraries/` 下是只读的板级支持库，**不要修改**，但可以读取头文件确认 API 签名。

{{FORBIDDEN_PROJECTS}}
---

## 1. 硬件拓扑

有两块板子，都是 STC32G：

- **主控板**：烧录程序的板子。只有 `MP74`、`MP03` 两个引脚能驱动舵机
  （用 `PWM_Init` / `PWM_SET_Duty`）。
- **机械拓展板**：承担绝大部分 IO 输出，引脚为
  `P60` `P62` `P64` `P66` `P74` `P75` `P76` `P77`。

**关键：`MP74` 与拓展板的 `P74` 不是同一个 IO。** 命名上加 `M` 前缀区分。

### 1.1 拓展板 IO 的唯一控制方式

拓展板引脚**只能**通过 `ExpansionBoradControl()` 控制，它通过 UART 把指令发给
拓展板。

**绝对不要**对拓展板引脚使用 `PWM_Init` / `PWM_SET_Duty` / `PWM_SET_Frequency`
——那些函数只作用于主控板的引脚，对拓展板无效。

```c
// 命令码
#define Init_Order        0xAA  // 初始化：参数为频率，50=舵机/摩擦轮，10000=电机
#define Duty_Change_Order 0xBB  // 修改占空比
#define Freq_Change_Order 0xCC  // 修改频率
#define Dir_Change_Order  0xDD  // 修改方向，1=正 0=负，设置一次即可
#define Zero_Order        0xEE  // 归零

void ExpansionBoradControl(uint8_t control_cmd,
        uint16_t data_p60, uint16_t data_p62, uint16_t data_p64, uint16_t data_p66,
        uint16_t data_p74, uint16_t data_p75, uint16_t data_p76, uint16_t data_p77);
```

使用顺序：**必须先发 `Init_Order` 设定频率**，之后才能改占空比。
每次调用 `ExpansionBoradControl` 之后**必须加 `Ms_Delay()`**，
防止数据传输失败并给硬件留响应时间。

### 1.2 引脚复用限制

部分外设共用同一路 PWM 信号，引脚号相同的不能同时使用。
例如用了 Motor5 电机，就不能再用第一路 P60 舵机。

---

## 2. C251 编译器限制

### 2.1 C89 模式

变量声明必须在代码块开头，不能在可执行语句之后。

```c
/* 错误：syntax error near 'int' */
void f(void) { foo(); int x = 1; }

/* 正确 */
void f(void) { int x = 1; foo(); }
```

### 2.2 int 是 16 位，且乘法不提升到 32 位

`common.h` 中 `typedef signed int int16_t`，上限 32767。
实测反汇编确认 `a * b` 编译为 `MUL WR6,WR2`（16 位乘法），
结果**不会**提升到 32 位，而且**溢出时编译器不报任何警告**。

```c
/* 危险：angle 超过 32 时溢出，静默出错 */
int duty = 750 + angle * 1000 / 180;

/* 安全做法一：用 float */
int duty = (int)(750.0f + angle * 5.5556f);

/* 安全做法二：先除后乘（牺牲精度） */
/* 安全做法三：显式转 long 做中间运算 */
int duty = 750 + (int)((long)angle * 1000 / 180);
```

### 2.3 math.h 没有 C99 的 float 后缀函数

用 `sqrt` / `fabs` / `acos` / `asin` / `atan2` / `sin` / `cos`，
**不要**用 `sqrtf` / `fabsf` / `acosf` / `atan2f` / `sinf` / `cosf`。
math.h 同时声明了 double 和 float 版本，C251 会按参数类型自动选择。

需要数学函数时 `#include "MATH.H"`（注意是大写）。

### 2.4 其他限制

- **不要用 `(void)x;` 消未使用参数的警告**：C251 不认这个惯用法，反而会触发
  `warning C138: expression with possibly no effect`。正确做法是直接删掉不用的
  参数。
- **C89 禁止零长数组**：数组维度为 0 会编译失败。如果某个配置项数量可能是 0，
  必须整块跳过数组定义、相关函数和调用点。
- **必须定义 `Channal`**：`nrf24l01.c` 通过 `extern uint8_t Channal` 引用它，
  main.c 里必须有定义：

```c
uint8_t Channal = 36;   /* 遥控器通道号，0~125 */
```

---

## 3. 舵机占空比约定

占空比是**万分比**（`CNU_PIE_PWM.h` 中 `PRECISION 10000.0f`），50Hz 下：

| 占空比 | 脉宽 | 角度 |
|--------|------|------|
| 250    | 0.5ms | -90°（行程一端）|
| 750    | 1.5ms | 0°（中位）|
| 1250   | 2.5ms | +90°（行程另一端）|

每度对应 `1000/180 ≈ 5.5556` 占空比。

**这是实测行程，不是标准 RC 舵机的 1~2ms（500~1000）区间。**
所有角度参数都按「相对中位的偏移角」理解，有效区间 ±90°。
超出 250~1250 的值会被硬件钳到端点。

---

## 4. 摩擦轮安全规程（硬性要求）

> 指南原文：若未按要求写程序导致摩擦轮或机械拓展板损坏，
> 需要由电控组员使用**人民币**赔偿。

违反以下任一条都可能烧毁电机或拓展板：

1. **初始化**：频率 50Hz，初始占空比 0%，
   初始化后**必须** `Ms_Delay(1000)` —— 留给硬件反应时间，否则电流过大。
2. **启动**：从占空比 500 开始，**每秒最多增加 100**，逐步提速。
   不得直接给到目标转速。
3. **上限 1100**（11%），未经允许不得超过。
4. **关闭**：同样逐步递减到 0，中间加延时。
   **不得在高速转动时直接断电。**
5. 程序里**必须有**关闭摩擦轮的逻辑。

启停时 0~5% 占空比区间可以跳过（电机在 5% 才开始转）。

```c
/* 正确的启动示例 */
ExpansionBoradControl(Duty_Change_Order, 0, 0, 500, 500, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 600, 600, 0, 0, 0, 0);
Ms_Delay(1500);
/* ... 以此类推 */
```

注意：主循环若是 10ms 一轮，则「每秒最多变 100」意味着每轮步长最多 1。

---

## 5. 电机

- 初始化频率 `10000` 表示该端口作为电机使用，`50` 表示作为舵机使用。
- 同一端口不能同时作为电机和舵机。
- 底盘电机速度范围通常 `-10000 ~ 10000`（负值靠 `Dir_Change_Order` 或符号处理）。

---

## 6. 常见陷阱

- `uint16_t` 变量不能直接取负：`-maxSpeed` 会触发
  `warning C115: '-' applied to unsigned type`，且结果仍是无符号数。
  需要负值时先转成 `int`。
- 舵机方向的实现**只能选一种**：要么在占空比计算里做镜像，
  要么发 `Dir_Change_Order`。两者叠加会互相抵消。
- 主循环里的阻塞延时会影响遥控响应，单次 `Ms_Delay` 不宜过长。

---

## 7. 如何编译（改完代码务必自己验证）

Windows 程序已内置 SDCC C251，不需要用户安装编译器。优先在程序顶部选择
“SDCC 编译”后点击“编译”。仅在用户明确要求 Keil 兼容验证时，才使用外置 Keil；
程序通过 `PIEBLOCK_KEIL` 环境变量或 `user://keil_settings.json` 获取安装目录。

从工作区根目录执行：

```powershell
# 以下命令仅用于明确要求的 Keil 兼容验证（PIEBLOCK_KEIL 指向外置 Keil 根目录）
$keil = $env:PIEBLOCK_KEIL
& "$keil/UV4/uVision.com" -r stc32g/Projects/ROBOMASTER_INFANTRY/MDK/Project_Template.uvproj -o build.log

# 工程构型
& "$keil/UV4/uVision.com" -r stc32g/Projects/ROBOMASTER_ENGINEER/MDK/Project_Template.uvproj -o build.log
```

改哪个 main.c 就编哪个工程。

**日志不在当前目录**：`-o` 的路径是相对 uvproj 所在目录解析的，
所以上面的命令把日志写到了 `Projects/<构型>/MDK/build.log`。
读的时候要带完整相对路径：

```powershell
Get-Content stc32g/Projects/ROBOMASTER_INFANTRY/MDK/build.log -Tail 10
```

几个必须知道的点：

- **用 `uVision.com`，不要用 `UV4.exe`**。后者是 GUI 程序，批处理时会弹窗抢焦点。
  两者在同一目录下。
- **退出码不可靠**，实测编译完全成功（`0 Error(s)`）时它也返回 1。
  **唯一**的成功判据是日志里出现 `0 Error(s)`。
- 日志开头那几条 `Registered ARM Compiler Version not found` 警告是**正常的**，
  本工具链已剔除 ARM 部分，STC32G 用不到，不必理会也不要试图修。
- 如果报找不到 `C251.EXE`，检查外置 Keil 的 `TOOLS.INI` 中 `[C251]` 段的 PATH；
  该文件由 Keil 安装程序维护。
- 编译产物（`Objects/` `Listings/` `*.lst`）已在 `.gitignore` 里，不用管。

如果没有外置 Keil，直接让用户在顶部选择“SDCC 编译”并点击「编译」。
本程序的用户是没有编程基础的学生，界面上只有一个「编译」按钮，
**不要**指导他们「打开 µVision 按 F7」。
