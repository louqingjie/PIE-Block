# STC32G12K128 无线固件升级系统技术报告

**pie-block 项目 · 2026-07-31**

## 摘要

本文报告一套面向 STC32G12K128（MCS-251 内核）的固件自升级系统。系统在芯片
Flash 的 `0xFF0000` 处常驻一个 4 KB 的自建 ISP 程序（bootloader），用户程序通过
约定命令字触发软复位交出控制权，由 bootloader 经串行链路接收并写入新固件。
全过程仅依赖一条透明串行通道，配合 HC-05/HC-06 一类蓝牙 SPP 模块即可实现无线
升级。

相比官方 STC-ISP 流程，本系统消除了四项人工操作：不需要外部烧录软件、不需要
离开编辑器、不需要物理接触设备、不需要断电或复位。

系统已在真机完成端到端验证：连续两次升级全程仅通过串行链路完成，30 KB 规模的
正式固件分 243 个数据块写入并全量读回校验通过。文中同时记录了实现过程中的四次
错误判断复盘，其参考价值不低于原理说明本身。

**关键词**：IAP、bootloader、MCS-251、Keil C251、OTA、无线烧录

## 1. 背景与目标

### 1.1 为什么需要它

pie-block 面向没有编程基础的大一学生。原固件更新流程是：

1. 配置参数，生成 `main.c`
2. Keil C251 编译
3. 切换到官方 STC-ISP 软件
4. 选芯片型号、配工作频率、选 hex
5. 点下载，然后给目标板上电

第 3~5 步是主要痛点：STC-ISP 参数配置易错、报错不可读；STC32G 的 ROM ISP 必须
在上电瞬间握手，**每次改代码都要物理接触设备**——对已装进机器人的主控板来说
意味着拆解。

### 1.2 设计目标

- **脱离 STC-ISP**：不依赖任何外部烧录软件
- **不离开编辑器**：编译与下载在同一界面完成
- **无线烧录**：物理链路可以是蓝牙 SPP，无需接线
- **无需下电 / 无需复位**：不依赖上电时序，不需要按复位键

### 1.3 技术路线

| 路线 | 评价 |
| --- | --- |
| 复用芯片 ROM ISP | 受 IRC 频率校准与 2400 波特率握手约束，且必须在上电瞬间介入，与「无需下电」目标冲突 |
| 字节码解释器 | 需要自建虚拟机与指令集，工作量与风险远超需求 |
| **自建 ISP（本文方案）** | Flash 常驻自写引导程序，协议自定，不依赖 ROM ISP |

自建 ISP 的可行性依据是 STC 官方完整参考实现（见附录 A）。本文的工作是在此
基础上完成移植、适配与缺陷修复。

## 2. 系统架构

```
┌──────────────────────────┐
│  pie-block (Godot)       │  图形化配置 -> 生成 main.c
│    └─ Keil C251          │  编译 -> App hex
│    └─ pie_block_iap.py   │  复位向量搬运 + 协议编解码
└───────────┬──────────────┘
            │  串行链路（USB-TTL 或蓝牙 SPP）
            │  对协议完全透明
┌───────────┴──────────────┐
│  STC32G12K128            │
│    0xFF0000  bootloader  │  4 KB，出厂烧一次，之后永不改动
│    0xFF1000  App 入口    │  中断向量、启动代码
│    0xFE0000  App 代码    │  用户函数体（60 KB 可用）
│    XRAM 0x1FFC  DfuFlag  │  下载请求标志
└──────────────────────────┘
```

### 2.1 无线链路与波特率限制

bootloader 与上位机之间只交换字节流，物理层对协议透明。蓝牙 SPP 模块接在
串口 1（P30/P31）上时，上位机看到的是一个 COM 口，与 USB-TTL 无异。

但「无线」并非免费。下载流程实际包含两段通信：

1. **触发阶段**：以 App 的 UART1 波特率（230400）发送 8 字节触发命令 `@PIEIAP#`，
   App 的 UART1 中断匹配后软复位
2. **升级阶段**：bootloader 复位后继续以统一波特率（230400）通信

USB-TTL 芯片（CH340/CP210x 等）可随时切换波特率，两段无缝衔接；蓝牙模块波特率
在配对时固定、**中途无法切换**，因此蓝牙链路两端现已统一为 230400。仍使用旧
115200 bootloader 的板子需通过官方 STC-ISP 物理升级一次，旧版不支持蓝牙一键重烧。
这一限制由 `toolchain.gd` 的 `bluetooth_baud_note()` 显式提示用户，不会自动处理。

另一个时序细节：Windows CH340 驱动的 `flush()` 只保证数据交给驱动，不保证 USB
芯片已按旧波特率把最后几字节发完。`pie_block_iap.py` 的 `TRIGGER_SETTLE_MIN`
（50 ms）正是为此引入——切换波特率前等待至少 50 ms，否则 `@PIEIAP#` 尾部被截断。

> **验证状态**：蓝牙链路 OTA **尚未实测**。本文全部真机数据均通过 CH340 取得。

### 2.2 与原流程对比

| 环节 | 原流程 | 本系统 |
| --- | --- | --- |
| 烧录软件 | 官方 STC-ISP | 编辑器内置 |
| 参数配置 | 每次手动选型号、频率 | 无 |
| 物理接触 | 每次都要 | 仅出厂烧底一次 |
| 上电时序 | 必须上电瞬间握手 | 无要求 |
| 复位操作 | 需要 | 无（软复位） |
| 链路 | USB 数据线 | USB 或蓝牙 |

### 2.3 编辑器侧集成

- **入口**：`ui.gd` 的「烧录主控板」按钮；`download_controller.gd` 在线程中执行
  下载，把 Python 逐行输出经 `call_deferred` 回传主线程
- **串口自动识别**：`toolchain.gd` 枚举 COM 口并按 VID/PID 分类，按可信度排序
  （USB 转串口 > 蓝牙 > 未知，排除系统虚拟口），逐个尝试、连上为止；蓝牙成对的
  「传入/传出」两个口自动跳过不对的那一个。中途擦除/写入/校验失败则停止遍历
- **进度显示**：日志关键行映射到阶段名与百分比
- **失败诊断**：按阶段（`port`/`connect`/`erase`/`program`/`verify`/`hex`/`env`）
  给针对性排查建议
- **编码处理**：Python 输出 UTF-8，Windows 中文环境下 `OS.execute` 按 GBK 解码
  会乱码，故走 `cmd /c` 重定向到日志文件再用 UTF-8 读取

## 3. Flash 空间划分与寻址

### 3.1 分区方案

```
物理地址
0xFE0000 ┌──────────────────────────┐
         │  低 64 K 块区             │  用户代码与数据（不可作为取指入口，见 3.3）
0xFEFFFF └──────────────────────────┘
0xFF0000 ┌──────────────────────────┐
         │  用户 ISP 代码区  4 K     │  ← bootloader
0xFF0FFF └──────────────────────────┘
0xFF1000 ┌──────────────────────────┐
         │  用户 AP 代码区  60 K     │  ← App 入口、中断向量、启动代码
0xFFFFFF └──────────────────────────┘
```

### 3.2 IAP 地址换算

IAP 通过 `IAP_ADDRE/ADDRH/ADDRL` 三个寄存器寻址，`IAP_ADDRE` 仅取 bit16，
故 IAP 地址空间为 17 位：

$$\text{IAP 地址} = \text{物理地址} \mathbin{\&} \mathtt{0x1FFFF}$$

| IAP 地址 | 物理地址 | 用途 |
| --- | --- | --- |
| `0x00000`–`0x0FFFF` | `0xFE0000`–`0xFEFFFF` | 用户代码与数据 |
| `0x10000`–`0x10FFF` | `0xFF0000`–`0xFF0FFF` | bootloader，禁止写入 |
| `0x11000`–`0x1FFFF` | `0xFF1000`–`0xFFFFFF` | App 入口与向量 |

### 3.3 低 64 K 区的取指约束

Phase 0 探针实测：将一段位置无关代码拷至 `0xFE0000` 后通过 far 指针调用，
**芯片立即复位**；XRAM 执行同样复位。精确表述为：

> `0xFE0000` 区不能作为**取指入口**，但位于该区的代码可通过 far 调用正常执行。

即程序入口与中断向量必须落在 `0xFF1000` 之后，而绝大部分函数体放低 64 K 无碍。
真机验证的 App 有 30 103 字节代码全部位于 `0xFE0000`，运行正常。

### 3.4 EEPROM 大小的前置条件

STC32G12K128 的 IAP 可写范围由 ISP 下载时设置的 EEPROM 大小决定。必须设为
**128 K**，否则全部 IAP 操作返回 `CMD_FAIL`。该设置**只在重新上电后生效**
（官方文档专门标注，仅按复位键无效）。

## 4. App 链接布局（全文最易错部分）

五项配置缺一不可，失效时多数不产生编译错误，仅表现为运行异常。

### 4.1 bootloader 侧：中断向量转发（isr.asm）

MCS-251 中断入口地址由硬件固定（`0x0003`、`0x000B` 起每 8 字节一个），落在
bootloader 的 4 KB 内。解法是在 bootloader 中放 67 条转发指令：
每个中断入口一条 `LJMP 原地址+0x1000`。**移植时必须包含 `isr.asm`**，遗漏将
导致 App 全部中断失效且不产生编译错误。

### 4.2 App 侧：`RomSize` = 4（方案成立的关键前提）

该选项决定代码 near（`CODE` 类）还是 far（`ECODE` 类）寻址。不修改时所有函数
编入 `CODE` 类，而 `CODE` 类基址恒为 `0xFF0000` 且不可修改——这正是「Keil 不
允许改代码基址」表象的真实成因。设为 4 后代码落入 `ECODE (0xFE0000-0xFFFFFF)`。
代价是代码体积增加约 4%（实测 25 563 → 26 572 字节）。

### 4.3 App 侧：`Ocm1` 段激活

```xml
<Ocm1>
  <Type>1</Type>                        <!-- 必须为 1 -->
  <StartAddress>0xfe0000</StartAddress>
  <Size>0x20000</Size>
</Ocm1>
```

`Type` 必须为 1。仅改地址与大小时整段被忽略，生成的 `.lnp` 中不会出现
`ECODE` 类。

### 4.4 App 侧：编译器选项 `INTVECTOR(0x1000)`

位置：uvproj 的 `<C251><VariousControls><MiscControls>`。将中断向量表推移至
偏移 `0x1000`，与 4.1 的转发指令对齐。注意它是**编译器**选项——在链接器配置中
找它是前期反复失败的直接原因。

### 4.5 App 侧：链接器选项 `CLASSES (CODE (0xFF1300-0xFFFFFF))`

位置：uvproj 的 `<Lx51><VariousControls><MiscControls>`。作用有三：

1. 把 `CODE` 类起点移出 bootloader 的 4 KB（仅移向量表不够——启动代码
   `?C_C51STARTUP` 等段仍会填入 `0xFF1003` 起）
2. 给上位机搬运复位向量预留 `0xFF1000`–`0xFF1002`
3. **跳过整个中断向量表区 `0xFF1003`–`0xFF11FF`**（67 入口 × 8 字节 = 536 字节）

**起点必须为 `0xFF1300`**。设为 `0xFF1003` 时链接器会把 `?CO?MAIN` 段（内含
`"@PIEIAP#"` 命令字常量）置于该处，正好占掉 interrupt 0 入口。现象是 App 完全
不启动，而写入、读回校验、bootloader 四重校验全部正常——极难定位。`pie_block_iap.py`
的 `check_vector_area()` 会逐个检查该区间字节是否为跳转指令（`0x02` LJMP 或
`0x8A` EJMP），非跳转则拒绝下载并指明被挤占的中断入口，正是为拦截这类错误而加。

### 4.6 App 侧：`HexSelection` = 1

bootloader 用 0（仅输出 `CODE` 段），App 必须用 1，否则 `ECODE` 段**不会写入
hex**。失效隐蔽：编译报告 `code=301` 而 hex 仅 48 字节，不产生任何警告。

### 4.7 上位机侧：复位向量搬运

App hex 在 `0xFF0000`–`0xFF0002` 的 3 字节长跳转需搬至 `0xFF1000`–`0xFF1002`：

- bootloader 占用 `0xFF0000`–`0xFF0FFF`，IAP 拒绝写入该区间
- bootloader 跳转前校验 `*(BYTE code *)(LDR_SIZE) == 0x02`，即物理 `0xFF1000`
  处必须为长跳转指令

实现见 `pie_block_iap.py` 的 `relocate_reset_vector()`。

### 4.8 配置正确后的目标布局

```
0xFE0000 起        用户代码（实测 24 736–30 209 字节）
0xFF0000-0xFF0002  3 字节 02 10 A7（长跳转至 0x10A7）
0xFF0003-0xFF0FFF  空 -> bootloader 安全
0xFF1000-0xFF1002  空洞 -> 待上位机搬入
0xFF1003-0xFF11FF  中断向量表区（INTVECTOR 放置 IV?n 的地方）
0xFF1300 起        命令字常量、启动代码、用户代码
```

核对手段：`python check_hex_layout.py <hex>`，确认 `app entry` 报告
「空洞(待搬入)」；下载前 `check_vector_area()` 再次把关。

## 5. 运行时机制

### 5.1 启动判断与断电保护

bootloader 上电后执行四重校验，全部通过才跳转 App（`dfu.c` 的 `dfu_check()`）：

```c
if ((DFU_FORCEPIN != 0) &&                          /* 引脚未被拉低 */
    (DfuFlag != DFU_TAG) &&                         /* 无下载请求标志 */
    (*(BYTE code *)(LDR_SIZE) == 0x02) &&           /* App 首字节为长跳转 */
    (*(WORD code *)(LDR_SIZE + 1) >= LDR_SIZE + 3)) /* 跳转目标跨过本区 */
{
    ((void (far *)())(0xff0000 + LDR_SIZE))();
}
```

第三、四重校验构成**断电保护**：升级中掉电时 App 首字节不为 `0x02`，bootloader
停在下载模式等待重传，不会跳入不完整固件。此设计比维护独立元数据扇区更省空间，
且不存在「元数据写入中掉电」的二阶失效路径。

### 5.2 下载请求标志置于 XRAM

```c
DWORD xdata DfuFlag _at_ 0x1ffc;   /* XRAM 末端 4 字节 */
```

软复位不清零 XRAM，因此 App 写标志后复位，bootloader 仍可读取。相比写 Flash：
不产生擦写磨损、无写入中掉电风险、App 侧仅两条语句：

```c
DfuFlag = 0x12abcd34;
IAP_CONTR = 0x20;      /* SWRST=1, SWBS=0 -> 复位至用户程序（bootloader） */
```

`IAP_CONTR = 0x20` 复位至**用户程序**，而非 `0x60` 进入 ROM ISP——这是「无需
下电、无需复位」成立的技术根据，绕开了 ROM ISP 对 IRC 校准与低速握手的依赖。

### 5.3 触发链路：UART1 ISR 内立即进入

App 侧触发逻辑由 `codegen_base.gd` 的 `_gen_isp_monitor()` 生成，注入每个 App
项目的 `main.c`；匹配逻辑在四个 App 项目的 `isr.c`（`UART1_Isr() interrupt 4`）：

```c
void UART1_Isr() interrupt 4
{
    ...
    if (UART1_GET_RX_FLAG)
    {
        UART1_CLEAR_RX_FLAG;
        dat = SBUF;
        if (dat == STCISPCMD[isp_cmd_index])
        {
            isp_cmd_index++;
            if (STCISPCMD[isp_cmd_index] == '\0')
            {
                isp_cmd_index = 0;
                iapDownloadReq = 1;
                iapEnterDownload();  /* 初始化可能阻塞，必须在 ISR 内立即进 bootloader */
            }
        }
        else
        {
            isp_cmd_index = 0;
            if (dat == STCISPCMD[isp_cmd_index])
                isp_cmd_index++;
        }
    }
}
```

**关键设计：匹配后必须在 ISR 内立即调用 `iapEnterDownload()`，不能只置标志等
主循环处理。** `remoteControlInitWithTimeout()`、`ExpansionBoradControl` 等外设
初始化可能永久等待未连接的硬件，主循环可能根本不会开始。`iapEnterDownload()`
内部关中断、写 DfuFlag、写 `IAP_CONTR=0x20`，不返回。主循环开头的
`if (iapDownloadReq) iapEnterDownload();` 保留为兜底，覆盖正常情形。

### 5.4 串口必须最先初始化

`_gen_uart_init_first()` 强制把 `UART_Init(UART_1, ...)` 放在所有外设初始化之前。
这是 OTA 的底线保障：某个外设没接好卡住初始化时（裸板没接遥控器时
`remote_control_init` 会卡、扩展板没接时 `ExpansionBoradControl` 也会等），芯片
仍能通过串口接收触发字重新下载，不至于只能靠 P32 拉低上电或拆机器用 STC-ISP 救。

### 5.5 完整时序

```
上位机发送 @PIEIAP# (230400 baud)
  └─ App 的 UART1 ISR 匹配命令字，调用 iapEnterDownload()
     └─ 关中断 -> 写 DfuFlag=0x12abcd34 -> IAP_CONTR=0x20 软复位
        └─ 芯片复位 -> bootloader 启动 (dfu_check)
           └─ 读到 DfuFlag == DFU_TAG，停留在下载模式
              ├─ CONNECT  -> 返回版本号 0x0200   (230400 baud)
              ├─ ERASE    -> 擦除 App 区（bootloader 自身受保护）
              ├─ PROGRAM  -> 分块写入
              ├─ READ     -> 读回校验
              └─ REBOOT   -> IAP_CONTR = 0x20，跳转新 App
```

### 5.6 地址保护

保护置于 IAP 最底层（`iap.c` 的 `iap_check_addr`），所有调用路径自动覆盖：

```c
BOOL iap_check_addr(DWORD addr)
{
    addr &= 0x1ffff;
    return ((addr < 0x10000) || (addr >= (0x10000 + LDR_SIZE)));
}
```

拒绝 IAP `0x10000`–`0x10FFF`，即 bootloader 自身。真机验证：ERASE 从 `0x00000`
遍历擦除至 `0x1FFFF`，bootloader 仍正常应答。

### 5.7 写入正确性的保障层级

`iap_write_byte()` 只检查 `CMD_FAIL`（`IAP_CONTR` B4 位），不做逐字节回读——
官方参考实现的逐字节 ecode 回读被证明不可靠（见 7.4），已移除。整体正确性由
PC 端下载后的全量读回校验（`IapSession.verify()`）保证，校验不可省略。

### 5.8 硬件逃生通道

**P32 拉低后上电** → 第一重校验不成立 → 无条件停留在下载模式。用于用户程序跑飞、
串口被占用等无法软件恢复的场景，真机验证 5/5 应答。官方参考实现用 P33，本项目
改用 P32（P33 是蜂鸣器）。P3 口占用：P30/P31 串口、P33 蜂鸣器、P34 遥控器复位、
P37 状态灯，仅 P32 空闲。

## 6. 通信协议

### 6.1 帧格式

沿用官方协议，便于调试期与官方上位机 `StcIsp_User.exe` 交叉对照。

```
上位机 -> 芯片:  '#' | len | cmd | payload... | '$' | 累加和
芯片 -> 上位机:  '@' | status | size | payload... | '$' | 累加和
```

- `len` 为 cmd 与 payload 的字节数之和
- 累加和取值使整帧字节之和的低 8 位归零

| 命令 | 编码 | payload |
| --- | --- | --- |
| CONNECT | `0xA0` | 无；返回 2 字节版本号 |
| READ | `0xA1` | addr(4, 小端) + size(1) |
| PROGRAM | `0xA2` | addr(4, 小端) + size(1) + data |
| ERASE | `0xA3` | 无 |
| REBOOT | `0xA4` | 无；不返回 |

状态码：`OK=0`、`ERRORCMD=1`、`OUTOFRANGE=2`、`PROGRAMERR=3`、`ERRORWRAP=0xFF`。

READ 命令需要 bootloader 编译时定义 `DEBUG`（`config.h` 已开启），否则回
`ERRORCMD`。没有 READ 就无法读回校验，只能靠「PROGRAM 没报错」推断，不足以
证明写对了。

### 6.2 面向不可靠链路的设计

- **命令级重传**：`IapSession.request()` 默认重试 3 次
- **帧同步恢复**：`recv()` 跳过帧头 `@` 前的噪声字节；校验失败的帧丢帧头重新
  同步，而不是放弃整次传输
- **非阻塞读取 + 外层 deadline**：Windows CH340 驱动偶尔不按 pyserial timeout
  结束大块重叠读取，校验阶段可能永久卡在 `read(256)`。串口保持非阻塞，只读驱动
  已报告到达的字节，外层 deadline 才能成为可靠硬截止
- **全量读回校验**：不依赖芯片侧逐字节回读（被证明不可靠）
- **失败可重入**：任一环节失败时 bootloader 保持在下载模式，可直接重试

### 6.3 协议一致性保障

`pie_block_iap.py` 的自测将真机抓取的帧字节序列固化为断言：

```python
check("CONNECT 帧", build_frame(CMD_CONNECT).hex(), "2301a02418")
check("ERASE 帧",   build_frame(CMD_ERASE).hex(),   "2301a32415")
check("REBOOT 帧",  build_frame(CMD_REBOOT).hex(),  "2301a42414")
```

后续修改协议时这些断言必须仍成立。自测可通过 `python pie_block_iap.py --selftest`
或 Godot 侧 `Toolchain.run_iap_selftest()` 运行，不需要串口和板子。

### 6.4 烧录前的 hex 校验

`hex_to_iap_chunks()` 在搬运复位向量前后做四重校验：

1. hex 必须有数据记录
2. `relocate_reset_vector()`：`0xFF0000` 处必须有 3 字节、首字节 `0x02`、跳转
   目标跨过 bootloader 区；搬运目标 `0xFF1000` 不得已被占用
3. `check_vector_area()`：向量表区字节必须是跳转指令（见 4.5）
4. 搬运后不得有任何字节落在 bootloader 保护区或超出 128K flash

任一不符都在打开串口前报错并指明原因，避免把错误固件写进去再排查。

## 7. 实现历程：错误判断复盘

保留这些记录，因为其参考价值不低于原理说明。

### 7.1 语境混淆导致的地址误判

`LDR_SIZE` 同时作为 code 空间偏移量与 IAP 地址计算参数出现，据此误推「hex 偏移
与 IAP 地址相差 `0x1000`，需要抓包确认」。实际换算为 `iap_addr = phys_addr &
0x1FFFF`，不含偏移。

**教训**：同一常量出现在不同语境时应显式区分。

### 7.2 结论适用范围的过度推广

探针实测 `0xFE0000` 区「调用即复位」，由此推出「App 无处可放」，一度转向字节码
解释器方案。结论本身正确，但适用范围被放大：不可取指 ≠ 不能执行。正确做法是
入口置于 `0xFF1000` 偏移处，函数体留在低 64 K。

**教训**：实测结论应精确表述边界条件。「不能执行」与「不能作为入口」是不同命题。

### 7.3 在错误的配置层反复尝试

前两轮集中于修改 uvproj 的 `<IROM>`、`<Cpu>`、`<CClasses>` 调整代码基址，全部
无效——`UseMemoryFromTarget=1` 时 `<CClasses>` 被忽略，`.lnp` 始终只有
`CLASSES (EDATA..., HDATA...)`。真正的答案是 `RomSize` 3→4 配合 `INTVECTOR`
**编译器**选项。**持续在链接器配置里找一个编译器选项**，直到下载官方参考实现
逐项比对才定位。

**教训**：同类尝试连续失败两次后应转向权威参考，而非在同一区域继续穷举。

### 7.4 取样偏差导致的连续误修

真机 PROGRAM 失败。测试 payload 长度 1、2、4、16、64、128，得到「仅长度 1 成功」
的观测，据此两次误修：加 `iap_verify_byte()` 回读（无效）、移除逐字节回读（无效），
各导致一次不必要的重新烧录。后续遍历长度 1~24，观测到真实规律是**严格的奇偶
交替**——整齐的规律只能源于确定性逻辑错误。根因见链接器 map 文件：
`UartRxBuffer` 位于 `0x21`（奇地址），`UartRxBuffer[2]` 在 `0x23` 亦为奇地址，
官方代码 `addr = *(DWORD *)&UartRxBuffer[2]` 构成**从奇地址执行 32 位读取**，
MCS-251 按对齐边界取字得到错位字节。改为逐字节拼装后解决。

**教训**：初始测试的六个长度除 1 外全为偶数，偏差直接导致误判；观测规律「过于
整齐」时应首先怀疑取样。另有一次二阶误判：自建 `request()` 在重试耗尽后统一抛
「写入失败」，实际部分情形是无应答——**观察原始字节比观察封装后的错误信息可靠**。

### 7.5 向量区被命令字挤占

链接器 CODE 起点最初设为 `0xFF1003`（与官方 demo 一致），链接器把 `?CO?MAIN`
段（含 `"@PIEIAP#"` 命令字常量）置于该处，正好占掉 interrupt 0 入口。现象是
App 完全不启动，而写入、读回校验、四重校验全部正常——所有诊断手段都显示
「没问题」。根因：官方 demo 在 `0xFF1000` 恰好空闲，未暴露此问题；段分配随编译
变化，不可依赖。最终把 CODE 起点抬到 `0xFF1300`，并加 `check_vector_area()`
做下载前校验。

**教训**：官方参考实现的「能跑」可能只是段分配的巧合；凡是依赖段布局的配置，
都应有独立校验手段守住。

### 7.6 参考实现中发现的两处缺陷

- **`dfu.c` 的 `UartInBuffer`**：DEBUG 分支引用不存在的变量（应为
  `UartTxBuffer`）。因该分支从未被编译，笔误长期留存
- **`dfu.c` 的引脚掩码**：P33 掩码 `0x08` 硬编码三处，仅改头文件会让上拉配置
  作用于蜂鸣器引脚，逃生通道失效且无警告。已抽取为 `DFU_FORCEPIN_MASK`

## 8. 验证结果

### 8.1 移植正确性验证

移植完成时（提交 `bf79a91`，仅改主频与引脚），编译产物 927 字节，与官方参考
实现字节级比对**仅差 7 字节**，每处均可对应明确改动（引脚掩码、位寻址 P32/P33、
BAUD）。该手段判别力显著强于「编译通过」。当前版本（997 字节）因修复缺陷并启用
`DEBUG`，与官方差 706 字节，字节级比对仅适用于移植验证阶段。

### 8.2 端到端升级验证

连续两次升级全程仅通过串行链路，未接触硬件：演示固件闪烁周期实测 502 ms /
100.5 ms，精确对应源码宏（500 ms / 100 ms），同时验证了中断转发机制生效
（延时完全依赖定时器 0 中断）。30 KB 正式固件：30 252 字节切分 243 块，
全部读回校验通过。

### 8.3 验证项汇总

| 验证项 | 状态 | 依据 |
| --- | --- | --- |
| bootloader ≤ 4 KB | 通过 | 997 字节 |
| 中断转发指令 | 通过 | hex 中 64/67 入口指向 +0x1000（官方同为 64/67） |
| 与官方一致性 | 通过 | 字节级比对仅 7 处差异 |
| CONNECT | 通过 | 返回版本号 0x0200 |
| ERASE 与自我保护 | 通过 | 全区擦除后仍能应答 |
| PROGRAM 各长度 | 通过 | 1–24 字节全部写入正确 |
| READ | 通过 | 读 IAP 0x10000 得到 bootloader 自身代码 |
| 30 KB 固件下载 | 通过 | 243 块读回校验全部通过 |
| ECODE 区可执行 | 通过 | 用户代码全部位于 0xFE0000，运行正常 |
| 中断转发至 App | 通过 | 定时器延时实测 100.5/502 ms |
| App 侧触发链路 | 通过 | 第二次升级经此进入 bootloader |
| ISR 内立即进 bootloader | 通过 | 主循环阻塞场景仍能下载 |
| P32 逃生通道 | 通过 | 5/5 应答 |
| 向量区校验 | 通过 | `check_vector_area` 拦截错误布局 |
| 编辑器内一键下载 | 通过 | `DownloadController` 端到端跑通 |
| 失败阶段分类与提示 | 通过 | `test_download_conn.gd` 回归 |
| **蓝牙 SPP 链路** | **未测** | 受两段波特率限制（见 2.1） |
| 断电中断保护 | **未测** | 仅代码层面论证（见 5.1） |

### 8.4 设计目标达成情况

| 目标 | 状态 | 说明 |
| --- | --- | --- |
| 脱离 STC-ISP | 达成 | 仅出厂烧底一次，由分发方完成 |
| 不离开编辑器 | 达成 | 编译+下载+进度+失败诊断均在 Godot 内完成 |
| 无线烧录 | 设计支持，未实测 | 物理层透明，但需统一波特率 |
| 无需下电 | 达成 | 软复位，不依赖上电时序 |
| 无需复位 | 达成 | 命令字触发，无物理操作 |

## 9. 未完成工作

- **蓝牙链路实测**：重点验证两段波特率切换在蓝牙链路上的处理，以及丢包率对
  243 块传输的影响
- **断电中断测试**：传输中断开链路，验证 bootloader 依据「App 首字节非 `0x02`」
  停留在下载模式（机制应成立，未实测）
- **连续多次升级压力测试**：目前最多验证连续两次
- **`codegen_debug.gd` 的 `Channal` 定义**：`nrf24l01.h` 通过 `extern uint8_t
  Channal` 引用它，其余三个生成器已包含定义，调试生成器缺少，使用其产物将链接
  失败（不参与日常编译路径，优先级低）

## 10. 维护注意事项

- **修改 `LDR_SIZE` 须三处同步**：`config.h`、`isr.asm` 的 `LDR_SIZE EQU`、
  所有 App uvproj 的 `INTVECTOR(...)`。遗漏任一处的表现为 App 静默不启动
- **修改协议须运行自测**：`python pie_block_iap.py --selftest`（含真机抓包固化
  的断言）
- **修改 uvproj 后须核对 hex**：`python check_hex_layout.py <hex>`，确认 `app
  entry` 报告「空洞(待搬入)」且 `0xFF0000` 处仅 3 字节；CODE 起点变更后还要确认
  向量表区未被普通段挤占
- **批量验证多个固件变体须用 `-r` 而非 `-b`**：`-b` 跳过重编译，多个变体会报告
  完全相同的 Program Size；判别依据是不同构型的 code/xdata 尺寸互不相同
- **更换蓝牙模块须核对波特率**：bootloader 的 `BAUD` 编译期写死（当前 230400，
  由 `config.h` 的 `FOSC` 推导）；旧 115200 bootloader 需官方 STC-ISP 物理升级
- **修改 uvproj 或库文件须同时改 `PROJECT_VERSION`**：位于 `scripts/toolchain.gd`。
  该常量不变时已运行用户的 `user://` 不更新，会拿旧配置编译且无提示——实际发生
  过：打完 bootloader 共存配置后 `user://` 仍为旧版，下载时报「0xFF1000 已被
  占用」，错误信息距真因很远
- **App 与 bootloader 波特率三处必须一致**：`codegen_base.gd` 的 `APP_BAUD`、
  `toolchain.gd` 的 `DEFAULT_APP_BAUD`、`pie_block_iap.py` 的
  `DEFAULT_APP_BAUD`。不一致时 App 收不到触发字，现象却是「bootloader 没有
  响应」。`test_download_conn.gd` 有断言守着
- **在项目目录放 Keil 产物须加 `.gdignore`**：Keil 目标文件 `.obj` 与 Wavefront
  OBJ 同名，Godot 会按 3D 模型解析刷错误。`stc32g/` 下已有 `.gdignore`，解压官方
  例程的临时目录需自行添加。`.gitignore`（版本控制）与 `.gdignore`（资源导入）
  互不相干

## 附录 A：参考资料

[1] STC 宏晶科技.《利用 STC 的 IAP 单片机开发自己的 ISP 程序——基于
STC32G12K128》. 官方例程包（`STC-official-user-UART-ISP-bootloader-demo-
STC32G12K128-series.zip`，来源：stcai.com「做自己的升级软件」页）。**本方案的
主要依据，遇疑问优先查阅。**

[2] STC 宏晶科技.《STC32G 系列单片机技术参考手册》. 第 905 页 `IAP_CONTR`
寄存器位定义（`CMD_FAIL` 位于 B4）；第 906 页 EEPROM 大小需在 ISP 下载时设置。

[3] Keil. *C251 Compiler / A251 Assembler / L251 Linker User's Guide*.
`INTVECTOR` 编译器控制、`CLASSES` 链接器控制、`RomSize` 与 near/far 寻址的关系。

## 附录 B：文件清单

### 芯片侧

```
stc32g/Projects/PIE_BOOTLOADER/
  USER/src/  main.c  dfu.c  iap.c  uart.c  isr.asm
  USER/inc/  config.h  dfu.h  iap.h  uart.h  stc.h  stc32g.h
  MDK/Project_Template.uvproj
  dist/pie_bootloader.hex     出厂烧录用，随套件分发
  dist/README.md              烧录参数说明
```

相对官方参考实现的改动仅三类：主频、引脚、7.4/7.6 的缺陷修复。其余源码保持原样，
便于继续与官方比对。

### 上位机侧

```
stc32g/toolchain/stcflash/
  pie_block_iap.py        协议实现、下载流程、hex 校验、脱机自测（--selftest）
  bootloader_probe.py     单命令探针，快速确认 bootloader 在线
  check_hex_layout.py     hex 地址布局核对，支持两个 hex 字节级比对
  pie_block_flash.py      旧 ROM ISP + stcgal 路径（兜底，日常不用）
```

### 编辑器侧

```
scripts/
  toolchain.gd            download_hex_iap() / 串口识别 / 失败分类 / 波特率提示
  download_controller.gd  线程化下载执行 + 进度映射 + 日志回传
  codegen/codegen_base.gd _gen_isp_monitor() 生成 App 侧触发代码
                          _gen_uart_init_first() 强制串口最先初始化
  ui.gd                   烧录按钮、进度条、失败诊断 UI
  test_download_conn.gd   串口分类/挑选/失败分类/波特率约束的回归测试
  test_iap_proto.gd       CRC-16 交叉验证（Python/C/GDScript 三方一致）
```

### 代码生成

`codegen_base.gd` 的 `_gen_isp_monitor()` 生成 App 侧的 `DfuFlag` 声明、
`iapEnterDownload()` 函数与主循环兜底检查；四个 App 项目的 `isr.c` 负责在 UART1
中断中匹配 `@PIEIAP#` 并立即进入 bootloader。

## 附录 C：已弃用的自研协议

项目早期自研过一套 bootloader（`stc32g/Projects/BOOTLOADER`），采用
`AA 55 | ver | cmd | addr(3) | len(2) | payload | crc16(2)` 帧格式与独立元数据
扇区方案。弃用原因：其地址布局假设 App 能链接到 `0xFF2000`，但实测改 uvproj 的
`<IROM>`/`<Cpu>`/`<CClasses>` 都不会进链接器。正解是官方例程的
`INTVECTOR(0x1000)` + `isr.asm` 蹦床 + 上位机搬复位向量三者配合（见第 4 节）。

弃用后保留的有价值产物：

- `stc32g/Libraries/deivers/src/iap_proto.c` 的 `iap_crc16()` /
  `iap_crc16_update()`（在 `IAP_PROBE` 探针上验证与 PC 侧逐位一致）
- `stc32g/Projects/BOOTLOADER/USER/src/main.c` 中直接操作 IAP 寄存器并检查
  `CMD_FAIL` 的原语（库函数 `EEPROM_*` 不检查 `CMD_FAIL`，不能用）
- `scripts/test_iap_proto.gd` 的 CRC-16 交叉验证与地址边界断言

`stc32g/Projects/BOOTLOADER/USER/src/main.c` 顶部已注明「已弃用，保留作参考」，
勿照此实施。
