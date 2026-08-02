# 基于自建 ISP 的 STC32G12K128 无线固件升级系统

**技术报告**

pie-block 项目 · 2026-07-31

---

## 摘要

本文报告一套面向 STC32G12K128（MCS-251 内核）的固件自升级系统的设计与实现。
系统在芯片 Flash 的 `0xFF0000` 处常驻一个 4 KB 的自建 ISP 程序（下称 bootloader），
用户程序通过约定的命令字触发软复位交出控制权，由 bootloader 经串行链路接收并写入
新固件。全过程仅依赖一条透明串行通道，配合 HC-05/HC-06 一类蓝牙 SPP 模块即可
实现无线升级。

相较于原有的官方 STC-ISP 工具链流程，本系统消除了四项人工操作：不需要打开外部
烧录软件、不需要离开编辑器、不需要物理接触设备、不需要断电或复位。

系统已在真机完成端到端验证：连续两次升级全程仅通过串行链路完成，30 KB 规模的
正式固件分 243 个数据块写入并全量读回校验通过。本文同时记录了实现过程中四次
错误判断的复盘，这部分内容对后续维护的价值不低于原理说明本身。

**关键词**：IAP、bootloader、MCS-251、Keil C251、OTA、无线烧录

---

## 1. 引言

### 1.1 问题背景

pie-block 是一套面向机器人竞赛的图形化电控编程环境，目标用户是负责机械结构设计的
大一学生 -- 多数没有编程基础，部分甚至缺乏机械设计经验。

原有的固件更新流程包含以下步骤：

1. 在 pie-block 中配置参数，生成 `main.c`
2. 调用 Keil C251 编译
3. 切换到官方 STC-ISP 软件
4. 在 STC-ISP 中选择芯片型号、配置工作频率、选择 hex 文件
5. 点击下载，然后给目标板上电

其中第 3 至第 5 步对目标用户构成显著负担。STC-ISP 的参数配置存在多个易错点，
配错后得到的失败提示对无经验用户几乎不可解读。更关键的是第 5 步：STC32G 的 ROM ISP
需要在上电瞬间完成握手，这意味着**每次修改代码都要物理接触设备**。对于已经装进
机器人本体的主控板，这往往意味着拆解。

### 1.2 设计目标

将"下载"归约为编辑器内的一次点击，且满足：

- **脱离 STC-ISP**：不依赖任何外部烧录软件
- **不离开编辑器**：编译与下载在同一界面完成
- **无线烧录**：物理链路可以是蓝牙 SPP，无需接线
- **无需下电**：不依赖上电时序
- **无需复位**：不需要按复位键或任何物理操作

### 1.3 技术路线选择

实现"程序自己替换自己"有三条常见路线：

| 路线 | 评价 |
|---|---|
| 复用芯片 ROM ISP | 受 IRC 频率校准与 2400 波特率握手约束，且必须在上电瞬间介入，与"无需下电"目标直接冲突 |
| 字节码解释器 | 用户程序变成解释执行的字节码，升级即替换数据。但需要自建虚拟机与指令集，工作量与风险远超需求 |
| **自建 ISP（本文方案）** | 在 Flash 中常驻一段自己的引导程序，协议自定，不依赖 ROM ISP |

第三条路线的可行性依据是 STC 官方提供的完整参考实现（见 §9 参考资料 [1]）。
本文的工作是在此基础上完成移植、适配与缺陷修复。

需要说明的是，第二条路线在实现过程中曾被短暂采纳 -- 当时因误判而认为第三条路线
不可行（见 §7.2）。这段弯路在 §7 中一并记录。此外，项目早期还自研过一套
`AA 55` 帧头 + CRC-16 的协议与配套 bootloader（`stc32g/Projects/BOOTLOADER`），
因地址布局方案被证伪而整体弃用，仅 IAP 原语与 CRC 实现被保留为库
（`stc32g/Libraries/deivers/src/iap_proto.c`），详见 §11。

---

## 2. 系统架构

### 2.1 总体结构

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

### 2.2 无线链路的实现方式与限制

bootloader 与上位机之间只交换字节流，物理层对协议透明。HC-05/HC-06 一类蓝牙
SPP 模块接在串口 1（P30/P31）上时，把蓝牙链路桥接成一条虚拟串口，上位机侧看到
的是一个 COM 口，与 USB-TTL 没有区别。

**但"无线"并非免费获得**。下载流程实际包含两段不同波特率的通信：

1. **触发阶段**：以 App 的 UART1 波特率（230400）发送 8 字节触发命令 `@PIEIAP#`，
   App 的 UART1 中断服务程序匹配后软复位
2. **升级阶段**：bootloader 复位后继续以统一波特率（230400）通信

USB-TTL 芯片（CH340/CP210x 等）可在运行时随时切换波特率，这两段通信无缝衔接。
蓝牙模块的波特率在配对时即固定，**中途无法切换**，因此走蓝牙链路时必须人工把
两端现已统一为 230400。仍使用旧 115200 bootloader 的板子需要通过官方
STC-ISP 物理升级一次；旧版不支持蓝牙一键重烧。这一限制在
`scripts/toolchain.gd` 的 `bluetooth_baud_note()` 中显式提示给用户，不会在
下载时自动处理 -- 统一波特率牵涉遥控器与调试工具的既有约定，不能由程序替用户决定。

触发字发送后还有一个时序细节：Windows CH340 驱动的 `flush()` 只保证数据已交给
驱动，不保证 USB 串口芯片已按旧波特率把最后几个字节发完。`pie_block_iap.py` 的
`TRIGGER_SETTLE_MIN`（50 ms）正是为此引入 -- 切换波特率前等待至少 50 ms，否则
`@PIEIAP#` 尾部会被截断，App 收不到完整命令。此约束由
`scripts/test_download_conn.gd` 的断言守护。

> **验证状态**：蓝牙链路的 OTA **尚未实测**。本文报告的全部真机数据均通过
> CH340（USB-TTL）取得。蓝牙模块与串口 1 共用 P30/P31 引脚，从协议角度看
> 除了上述波特率限制外不需要任何改动，但"设计上支持"与"已验证"是两回事，
> 此处不作过度声称。

### 2.3 与原流程的对比

| 环节 | 原流程 | 本系统 |
|---|---|---|
| 烧录软件 | 官方 STC-ISP | 编辑器内置 |
| 参数配置 | 每次手动选型号、频率 | 无 |
| 物理接触 | 每次都要 | 仅出厂烧底那一次 |
| 上电时序 | 必须在上电瞬间握手 | 无要求 |
| 复位操作 | 需要 | 无（软复位） |
| 链路 | USB 数据线 | USB 或蓝牙 |

出厂烧底那一次仍需 STC-ISP，但它由套件分发方完成（参数见
`stc32g/Projects/PIE_BOOTLOADER/dist/README.md`），不落到最终用户头上。

### 2.4 编辑器侧的下载集成

下载路径已完整接入 pie-block 的 Godot 界面，不再是命令行工具：

- **入口**：`scripts/ui.gd` 的"烧录主控板"按钮（`VBoxContainer/TopPanel/Download`），
  编译成功后可一键触发。`scripts/download_controller.gd` 负责在线程中执行下载、
  把 Python 脚本的逐行输出通过 `call_deferred` 回传主线程显示
- **串口自动识别**：`scripts/toolchain.gd` 的 `list_serial_ports_detailed()` 枚举
  所有 COM 口并按 VID/PID 分类（`_classify_port`），`pick_download_port()` 按优先级
  挑选：USB 转串口 > 蓝牙 > 未知 > 虚拟口。同类型多个时不猜，把候选都列给用户
- **进度显示**：`_progress_from_log_line()` 把 Python 脚本的关键日志行映射到
  阶段名与百分比（触发 -> 连接 -> 擦除 -> 写入 -> 校验 -> 重启），实时刷新进度条
- **失败诊断**：`_classify_iap_failure()` 从日志判断失败阶段
  （`port`/`connect`/`erase`/`program`/`verify`/`hex`/`env`），
  `iap_failure_hint()` 翻译成给无嵌入式背景用户的可执行排查建议
- **编码处理**：Python 脚本输出 UTF-8，但 `OS.execute` 的 output 数组在 Windows
  中文环境按 GBK 解码会乱码，故下载路径走 `cmd /c` 重定向到日志文件再用
  `FileAccess.get_file_as_string`（UTF-8）读取，与编译路径对齐

---

## 3. Flash 空间划分与寻址模型

### 3.1 分区方案

分区取自官方文档 [1] 第 2 页：

```
物理地址
0xFE0000 ┌──────────────────────────┐
         │  低 64 K 块区             │  用户代码与数据（不可作为取指入口，见 §3.3）
0xFEFFFF └──────────────────────────┘
0xFF0000 ┌──────────────────────────┐
         │  用户 ISP 代码区  4 K     │  ← bootloader
0xFF0FFF └──────────────────────────┘
0xFF1000 ┌──────────────────────────┐
         │  用户 AP 代码区  60 K     │  ← App 入口、中断向量、启动代码
0xFFFFFF └──────────────────────────┘
```

### 3.2 IAP 地址换算

IAP 操作通过 `IAP_ADDRE/ADDRH/ADDRL` 三个寄存器寻址，其中 `IAP_ADDRE` 仅取 bit16
（芯片侧实现为 `IAP_ADDRE = BYTE2(addr) & 0x01`），故 IAP 地址空间为 17 位：

$$\text{IAP 地址} = \text{物理地址} \mathbin{\&} \mathtt{0x1FFFF}$$

| IAP 地址 | 物理地址 | 用途 |
|---|---|---|
| `0x00000`–`0x0FFFF` | `0xFE0000`–`0xFEFFFF` | 用户代码与数据 |
| `0x10000`–`0x10FFF` | `0xFF0000`–`0xFF0FFF` | bootloader，禁止写入 |
| `0x11000`–`0x1FFFF` | `0xFF1000`–`0xFFFFFF` | App 入口与向量 |

换算仅为一次按位与，不含偏移。此结论曾被误判（见 §7.1）。

### 3.3 低 64 K 区的取指约束

Phase 0 探针（`stc32g/Projects/IAP_PROBE`）实测：将一段位置无关代码拷至
`0xFE0000` 后通过 far 指针调用，**芯片立即复位**；XRAM 执行同样复位。

该事实的精确表述为：

> `0xFE0000` 区不能作为**取指入口**，但位于该区的代码可通过 far 调用正常执行。

区别在于程序入口与中断向量必须落在 `0xFF1000` 之后，而绝大部分函数体放在低 64 K
并无问题。真机验证的 App 有 30 103 字节代码全部位于 `0xFE0000`，运行正常。

对这一约束的过度推广曾导致方案被误判为不可行，详见 §7.2。

### 3.4 EEPROM 大小的前置条件

STC32G12K128 的 IAP 可写范围由 ISP 下载时设置的 EEPROM 大小决定（手册 [2] 第 906 页）。
必须设为 **128 K**，否则全部 IAP 操作返回 `CMD_FAIL`。

该设置**只在重新上电后生效**，官方文档专门标注"重要，容易被忽略"。仅按复位键无效。

---

## 4. App 链接布局：必需配置

本节是全文最易出错的部分。五项配置缺一不可，且失效时多数不产生编译错误，
仅表现为运行异常。

### 4.1 bootloader 侧：中断向量转发

MCS-251 的中断入口地址由硬件固定（`0x0003`、`0x000B`，此后每 8 字节一个），
这些地址落在 bootloader 占用的 4 KB 内。解法是在 bootloader 中放置 67 条转发指令
（`stc32g/Projects/PIE_BOOTLOADER/USER/src/isr.asm`）：

```asm
LDR_SIZE    EQU     1000H

MAPISR      MACRO   ADDR
            CSEG    AT  ADDR
            LJMP    LDR_SIZE + $
            ENDM

            MAPISR  0003H
            MAPISR  000BH
            ...
```

每个中断入口放一条长跳转指向 `原地址 + 0x1000`。移植时**必须包含 `isr.asm`**，
遗漏将导致 App 的全部中断失效，且不产生编译错误。

### 4.2 App 侧：`RomSize` = 4

**此项为方案成立的关键前提。**

该选项决定代码采用 near（`CODE` 类）还是 far（`ECODE` 类）寻址。若不修改，
所有函数编入 `CODE` 类，而 **`CODE` 类基址恒为 `0xFF0000` 且不可修改** --
这正是"Keil 不允许修改代码基址"这一表象的真实成因。设为 4 后代码自然落入
`ECODE (0xFE0000-0xFFFFFF)`。

代价为代码体积增加约 4%（far 调用指令更长），实测 25 563 -> 26 572 字节。

### 4.3 App 侧：`Ocm1` 段激活

```xml
<Ocm1>
  <Type>1</Type>                        <!-- 必须为 1 -->
  <StartAddress>0xfe0000</StartAddress>
  <Size>0x20000</Size>
</Ocm1>
```

`Type` 必须为 1。仅修改地址与大小时整段被忽略，生成的 `.lnp` 中不会出现 `ECODE` 类。

### 4.4 App 侧：编译器选项 `INTVECTOR(0x1000)`

位置：uvproj 的 `<C251><VariousControls><MiscControls>`。

将中断向量表推移至偏移 `0x1000`，与 §4.1 的转发指令对齐。

需注意两点：其一，该选项**仅移动中断向量，不移动代码基址**；其二，它是
**编译器**选项而非链接器选项 -- 在链接器配置中寻找此功能是前期反复失败的直接原因
（见 §7.3）。

### 4.5 App 侧：链接器选项 `CLASSES (CODE (0xFF1300-0xFFFFFF))`

位置：uvproj 的 `<Lx51><VariousControls><MiscControls>`。作用有三：

1. 将 `CODE` 类起点移出 bootloader 的 4 KB。仅移动向量表不足 -- 启动代码
   `?C_C51STARTUP` 等段仍会填入 `0xFF1003` 起的空间
2. 给上位机搬运复位向量预留 `0xFF1000`–`0xFF1002`
3. **跳过整个中断向量表区 `0xFF1003`–`0xFF11FF`**（67 个入口 × 8 字节 = 536 字节）

**起点必须为 `0xFF1300`**。设为 `0xFF1003` 时链接器会把 `?CO?MAIN` 段（内含
`"@PIEIAP#"` 命令字常量）置于该处，正好占掉 interrupt 0 的入口。现象是 App 完全
不启动，而写入、读回校验、bootloader 的四重校验判据全部正常 -- 极难定位
（这一坑实际发生过，详见 §7.5）。向量表末尾 `0xFF11FB` 的 MAPISR 转发目标占 4
字节，到 `0xFF11FF`（含），CODE 起点必须落在此之后。当前约定取 `0xFF1300`
（对齐到 0x100 边界并留一格余量），`pie_block_iap.py` 的 `VECTOR_AREA_END`
据此设为 `0xFF11FF`。

`pie_block_iap.py` 的 `check_vector_area()` 会逐个检查 `0xFF1003`–`0xFF11FF`
区间内的字节是否为跳转指令（`0x02` LJMP 或 `0x8A` EJMP），非跳转数据则拒绝下载
并指明是哪个 interrupt 入口被挤占，正是为拦截这类配置错误而加。

### 4.6 App 侧：`HexSelection` = 1

bootloader 使用 0（仅输出 `CODE` 段），App 必须使用 1，否则 `ECODE` 段代码
**不会写入 hex**。此失效尤为隐蔽：编译报告 `code=301` 而 hex 仅 48 字节，
不产生任何警告。

### 4.7 上位机侧：复位向量搬运

App hex 在 `0xFF0000`–`0xFF0002` 处有 3 字节长跳转指令，需搬移至
`0xFF1000`–`0xFF1002`。理由有两条：

- bootloader 占用 `0xFF0000`–`0xFF0FFF`，IAP 拒绝写入该区间
- bootloader 跳转前校验 `*(BYTE code *)(LDR_SIZE) == 0x02`，即物理 `0xFF1000`
  处必须为长跳转指令

官方文档 [1] 第 5 页明确此责任归属：「重映射的工作上位机应用程序会自动处理，
用户在编写 AP 代码时无需关心」。实现见 `pie_block_iap.py` 的
`relocate_reset_vector()`。

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
"空洞(待搬入)"；`pie_block_iap.py` 下载前的 `check_vector_area()` 会再次把关。

---

## 5. 运行时机制

### 5.1 启动判断与断电保护

bootloader 上电后执行四重校验，全部通过方跳转至 App（`dfu.c` 的 `dfu_check()`）：

```c
if ((DFU_FORCEPIN != 0) &&                          /* 引脚未被拉低 */
    (DfuFlag != DFU_TAG) &&                         /* 无下载请求标志 */
    (*(BYTE code *)(LDR_SIZE) == 0x02) &&           /* App 首字节为长跳转 */
    (*(WORD code *)(LDR_SIZE + 1) >= LDR_SIZE + 3)) /* 跳转目标跨过本区 */
{
    ((void (far *)())(0xff0000 + LDR_SIZE))();
}
```

第三、四重校验同时构成**断电保护**：升级过程中掉电时 App 首字节不为 `0x02`，
bootloader 将停在下载模式等待重传，不会跳入不完整的固件。

此设计比维护独立的元数据扇区更节省空间，且不存在"元数据写入过程中掉电"的
二阶失效路径。

### 5.2 下载请求标志置于 XRAM

```c
DWORD xdata DfuFlag _at_ 0x1ffc;   /* XRAM 末端 4 字节 */
```

软复位不清零 XRAM，因此 App 写入标志后复位，bootloader 仍可读取。

相较于将标志写入 Flash 的方案，本设计的优势在于：不产生 Flash 擦写磨损、
不存在标志写入过程中掉电的风险、App 侧仅需两条语句：

```c
DfuFlag = 0x12abcd34;
IAP_CONTR = 0x20;      /* SWRST=1, SWBS=0 -> 复位至用户程序 */
```

`IAP_CONTR = 0x20` 复位至**用户程序**（即 bootloader），而非 `0x60` 那样进入
ROM ISP。这一区别是"无需下电、无需复位"能够成立的技术根据 -- 它绕开了 ROM ISP
对 IRC 频率校准与低速握手的依赖。

### 5.3 触发链路：UART1 ISR 内立即进入

App 侧的触发逻辑由 `scripts/codegen/codegen_base.gd` 的 `_gen_isp_monitor()`
生成，注入到每个 App 项目的 `main.c`；匹配逻辑在四个 App 项目的 `isr.c`
（`UART1_Isr() interrupt 4`）中：

```c
extern char code STCISPCMD[];          /* "@PIEIAP#" */
extern uint8_t isp_cmd_index;
extern volatile uint8_t iapDownloadReq;
extern void iapEnterDownload(void);

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
主循环处理。** 原因是 `remoteControlInitWithTimeout()`、`ExpansionBoradControl`
等外设初始化可能永久等待未连接的硬件，主循环可能根本不会开始，那时再等主循环
检查 `iapDownloadReq` 就永远等不到了。`iapEnterDownload()` 内部关中断、写 DfuFlag、
写 `IAP_CONTR=0x20`，不返回。

主循环开头的 `if (iapDownloadReq) iapEnterDownload();` 保留为兜底，覆盖
"主循环已在运行时收到触发字"的正常情形。

### 5.4 串口必须最先初始化

`_gen_uart_init_first()` 强制把 `UART_Init(UART_1, ...)` 放在所有外设初始化之前。
这是 OTA 的底线保障：一旦某个外设没接好卡住初始化（裸板没接遥控器时
`remote_control_init` 会卡、扩展板没接时 `ExpansionBoradControl` 也会等），
芯片仍能通过串口接收触发字重新下载程序，不至于只能靠 P32 拉低上电或重新用
STC-ISP 烧录来救。这对目标用户尤其重要 -- 他们的接线错误是常态，不该因此就要
拆机器。

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

下载全过程固定使用 230400，不再在 App 与 bootloader 之间切换波特率
（见 §2.2 对蓝牙链路的限制说明）。

### 5.6 地址保护

保护置于 IAP 最底层（`iap.c` 的 `iap_check_addr`），所有调用路径自动覆盖：

```c
BOOL iap_check_addr(DWORD addr)
{
    addr &= 0x1ffff;
    return ((addr < 0x10000) || (addr >= (0x10000 + LDR_SIZE)));
}
```

拒绝 IAP `0x10000`–`0x10FFF`，即 bootloader 自身。真机验证：ERASE 命令
从 `0x00000` 遍历擦除至 `0x1FFFF`，执行完毕后 bootloader 仍正常应答。

### 5.7 写入正确性的保障层级

`iap_write_byte()` 只检查 `CMD_FAIL`（`IAP_CONTR` 的 B4 位），**不做逐字节回读**。
官方参考实现里的逐字节 ecode 回读被证明不可靠（见 §7.4），已移除。整体正确性
由 PC 端下载后的全量读回校验（`IapSession.verify()`）保证 -- PROGRAM 只报
`CMD_FAIL`，不保证内容真的对，故校验不可省略。

### 5.8 硬件逃生通道

**P32 拉低后上电** -> 第一重校验不成立 -> 无条件停留在下载模式。

用于用户程序跑飞、串口被占用等无法通过软件恢复的场景。真机验证 5/5 应答。

官方参考实现使用 P33，本项目改用 P32 -- P33 在本项目中为蜂鸣器。P3 口占用情况：
P30/P31 串口、P33 蜂鸣器、P34 遥控器复位、P37 状态灯，仅 P32 空闲。

---

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
|---|---|---|
| CONNECT | `0xA0` | 无；返回 2 字节版本号 |
| READ | `0xA1` | addr(4, 小端) + size(1) |
| PROGRAM | `0xA2` | addr(4, 小端) + size(1) + data |
| ERASE | `0xA3` | 无 |
| REBOOT | `0xA4` | 无；不返回 |

状态码：`OK=0`、`ERRORCMD=1`、`OUTOFRANGE=2`、`PROGRAMERR=3`、`ERRORWRAP=0xFF`。

READ 命令需要 bootloader 编译时定义 `DEBUG`（`config.h` 已开启），否则回
`ERRORCMD`。没有 READ 就无法读回校验，只能靠"PROGRAM 没报错"推断，不足以证明
写对了。

### 6.2 面向不可靠链路的设计

蓝牙链路的丢包率与延迟高于有线，协议层因此保留以下机制：

- **命令级重传**：`IapSession.request()` 默认重试 3 次
- **帧同步恢复**：`recv()` 跳过帧头 `@` 之前的任意噪声字节（App 复位时的乱码）；
  遇到校验失败的帧丢弃帧头重新同步，而非放弃整次传输
- **非阻塞读取 + 外层 deadline**：Windows CH340 驱动偶尔不按 pyserial 的 timeout
  结束大块重叠读取，校验阶段会永久卡在 `read(256)`。串口保持非阻塞，只读取驱动
  已报告到达的字节，外层 deadline 才能成为可靠的硬截止时间
- **全量读回校验**：写入完成后逐块读回比对，不依赖芯片侧的逐字节回读
  （后者被证明不可靠，见 §7.4）
- **失败可重入**：任一环节失败时 bootloader 保持在下载模式，可直接重试

### 6.3 协议一致性保障

`pie_block_iap.py` 的自测将真机抓取的帧字节序列固化为断言：

```python
check("CONNECT 帧", build_frame(CMD_CONNECT).hex(), "2301a02418")
check("ERASE 帧",   build_frame(CMD_ERASE).hex(),   "2301a32415")
check("REBOOT 帧",  build_frame(CMD_REBOOT).hex(),  "2301a42414")
```

后续修改协议时这些断言必须仍然成立，否则芯片侧无法解析。自测可通过
`python pie_block_iap.py --selftest` 或 Godot 侧的
`Toolchain.run_iap_selftest()` 运行，不需要串口也不需要板子。

### 6.4 烧录前的 hex 校验

`hex_to_iap_chunks()` 在搬运复位向量前后做四重校验：

1. hex 必须有数据记录
2. `relocate_reset_vector()`：`0xFF0000` 处必须有 3 字节、首字节为 `0x02`、
   跳转目标跨过 bootloader 区；搬运目标 `0xFF1000` 不得已被占用
3. `check_vector_area()`：中断向量表区内的字节必须是跳转指令（见 §4.5）
4. 搬运后不得有任何字节落在 bootloader 保护区或超出 128K flash

任一不符都会在打开串口之前就报错并指明原因，避免把错误固件写进去后再排查。

---

## 7. 实现历程：四次错误判断的复盘

本节记录实现过程中的错误判断。保留它的理由是这些错误呈现出可归纳的模式，
其参考价值不低于原理说明。

### 7.1 语境混淆导致的地址误判

`LDR_SIZE` 同时作为 code 空间偏移量与 IAP 地址计算的参数出现。笔者据此推断
"hex 偏移与 IAP 地址相差 `0x1000`，需要抓包确认"。

实际换算为 `iap_addr = phys_addr & 0x1FFFF`，不含偏移。查阅官方文档 [1] 第 2 页的
分区图并实测解析两个 hex 即可定论，无需抓包。

**教训**：同一常量出现在不同语境时应显式区分，不应依赖记忆维持一致性。

### 7.2 结论适用范围的过度推广

探针实测 `0xFE0000` 区"调用即复位"，XRAM 同样如此。笔者由此推出"App 无处可放"，
并一度转向研究字节码解释器方案。

结论本身正确，但**适用范围被放大**：不可取指指的是不能作为入口，不代表该区代码
无法通过 far 调用执行。正确做法是将入口置于同一代码区的偏移处 `0xFF1000`，
函数体保留在低 64 K。

**教训**：实测结论应精确表述边界条件。"不能执行"与"不能作为入口"是不同命题，
含糊表述会在后续推理中被放大为错误结论。

### 7.3 在错误的配置层反复尝试

前两轮工作集中于修改 uvproj 的 `<IROM>`、`<Cpu>`、`<CClasses>` 以调整代码基址，
全部无效 -- 生成的 `.lnp` 中始终仅有 `CLASSES (EDATA..., HDATA...)`。
（成因后来查明：`UseMemoryFromTarget=1` 时 `<CClasses>` 被忽略。）

真正的答案是 `RomSize` 3->4 配合 `INTVECTOR` **编译器**选项。**笔者持续在链接器
配置中寻找一个编译器选项。**

此轮消耗时间最多，直至下载官方参考实现逐项比对才定位。

**教训**：同类尝试连续失败两次后应转向查找权威参考，而非在同一配置区域内继续
穷举。官方参考实现始终公开可得，提前查阅可节省两轮工作。

### 7.4 取样偏差导致的连续误修

真机 PROGRAM 命令失败。笔者测试 payload 长度 1、2、4、16、64、128，
得到"仅长度 1 成功"的观测，据此判断为回读校验的时序问题，并作了两次修改：

1. 增加 `iap_verify_byte()` 改用 IAP 命令回读 -- 无效
2. 移除逐字节回读 -- 无效

两次均无效，且各导致一次不必要的重新烧录。

后续遍历长度 1 至 24，观测到真实规律为**严格的奇偶交替**。该规律的整齐程度
只能源于确定性的逻辑错误，不可能是时序问题。

根因见于链接器 map 文件：

```
00000021H   EDATA    UartRxBuffer
```

`UartRxBuffer` 位于 `0x21`（奇地址），故 `UartRxBuffer[2]` 位于 `0x23`，亦为奇地址。
官方代码 `addr = *(DWORD *)&UartRxBuffer[2]` 构成**从奇地址执行 32 位读取**，
MCS-251 按对齐边界取字，得到错位的字节组合。改为逐字节拼装后问题消除
（见 `dfu.c` 的 `dfu_events()`）。

**教训**（两条）：

- 初始测试的六个长度中除 1 以外全为偶数，此偏差直接导致误判。观测规律
  "过于整齐"时应首先怀疑取样，而非急于解释。
- 过程中存在一次二阶误判：自建的 `request()` 在重试耗尽后统一抛出"写入失败"，
  笔者据此认为全部失败均为 `PROGRAM_ERR`，实际部分情形为无应答。
  **观察原始字节比观察封装后的错误信息可靠。**

### 7.5 向量区被命令字挤占

链接器 CODE 起点最初设为 `0xFF1003`（与官方 demo 一致），链接器把 `?CO?MAIN`
段（内含 `"@PIEIAP#"` 命令字常量）置于该处，正好占掉 interrupt 0 的入口。
现象是 App 完全不启动，而写入、读回校验、bootloader 的四重校验判据全部正常 --
所有诊断手段都显示"没问题"，唯独 App 不跑。

根因：官方 demo 在 `0xFF1000` 恰好空闲，未暴露此问题；段分配随编译结果变化，
不可依赖。最终把 CODE 起点抬到 `0xFF1300` 跳过整个向量表区，并在
`pie_block_iap.py` 加了 `check_vector_area()` 做下载前校验，防止再犯。

**教训**：官方参考实现的"能跑"可能只是段分配的巧合，不能当作通用结论。
凡是依赖段布局的配置，都应有独立的校验手段守住。

### 7.6 参考实现中发现的两处缺陷

**`dfu.c` 的 `UartInBuffer`**：DEBUG 分支引用了一个不存在的变量。因该分支从未
被编译，笔误得以长期留存。应为 `UartTxBuffer`。

**`dfu.c` 的引脚掩码**：`DFU_FORCEPIN` 定义于 `dfu.h`，但 `dfu.c` 中将 P33 的
掩码 `0x08` 硬编码于三处。仅修改头文件会使上拉配置作用于蜂鸣器引脚，
逃生通道失效且不产生任何警告。已抽取为 `DFU_FORCEPIN_MASK`。

---

## 8. 验证结果

### 8.1 移植正确性验证

移植完成时（提交 `bf79a91`，仅修改主频与引脚，尚未修复缺陷），编译产物 927 字节，
与官方参考实现作字节级比对**仅相差 7 字节**，且每处均可对应到明确改动：

| 地址 | 本项目 | 官方 | 对应改动 |
|---|---|---|---|
| `0x2B0` | `FB` | `F7` | `~0x04` vs `~0x08` |
| `0x2BD`/`0x2FF`/`0x310` | `04` | `08` | 引脚掩码 |
| `0x2C9` | `B2` | `B3` | 位寻址 P32 vs P33 |
| `0x465`/`0x4D8` | - | - | BAUD 65484 -> 65464 |

该手段的判别力显著强于"编译通过"，可证明不存在意外副作用。移植类工作值得
专门执行一次此类比对。

当前版本（997 字节）与官方相差 706 字节，因后续修复了 §7.4/§7.6 的缺陷并启用了
`DEBUG`（READ 命令），代码结构已发生变化。故字节级比对仅适用于移植验证阶段，
之后应转向功能测试。

### 8.2 端到端升级验证

连续两次升级，全程仅通过串行链路完成，未接触硬件：

| 项目 | 第一版 | 第二版 |
|---|---|---|
| 每周期连发字节数 | 60 | 10 |
| 闪烁周期（设计值） | 500 ms | 100 ms |
| 闪烁周期（实测） | 502 ms | 100.5 ms |
| 实测样本 | 502/503/502/502 | 101/100/100/101/100 |

节奏精确对应源码中的宏定义。演示固件的延时完全依赖定时器 0 中断累加计数，
中断未能进入时将无限等待 -- 因此该数据同时验证了 §4.1 的中断转发机制生效。

30 KB 规模的正式固件同样下载成功：30 252 字节切分为 243 个数据块，
全部读回校验通过。

### 8.3 验证项汇总

| 验证项 | 状态 | 依据 |
|---|---|---|
| bootloader ≤ 4 KB | 通过 | 997 字节 |
| 中断转发指令 | 通过 | hex 中 64/67 入口指向 +0x1000（官方同为 64/67）|
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
| **蓝牙 SPP 链路** | **未测** | 见 §2.2，受两段波特率限制 |
| 断电中断保护 | **未测** | 仅代码层面论证，见 §10 |

### 8.4 设计目标达成情况

| 目标 | 状态 | 说明 |
|---|---|---|
| 脱离 STC-ISP | 达成 | 仅出厂烧底一次，由分发方完成 |
| 不离开编辑器 | 达成 | 编译+下载+进度+失败诊断均在 Godot 内完成 |
| 无线烧录 | 设计支持，未实测 | 物理层对协议透明，但需统一波特率，见 §2.2 |
| 无需下电 | 达成 | 软复位，不依赖上电时序 |
| 无需复位 | 达成 | 命令字触发，无物理操作 |

---

## 9. 参考资料

[1] STC 宏晶科技.《利用 STC 的 IAP 单片机开发自己的 ISP 程序 -- 基于
STC32G12K128》. 官方例程包
`STC-official-user-UART-ISP-bootloader-demo-STC32G12K128-series.zip`，
来源：stcai.com「做自己的升级软件」页. 包含 PDF 说明、bootloader 源码、
演示 App 与上位机程序。**本方案的主要依据，遇疑问优先查阅。**

[2] STC 宏晶科技.《STC32G 系列单片机技术参考手册》. 第 905 页 `IAP_CONTR`
寄存器位定义（`CMD_FAIL` 位于 B4）；第 906 页 EEPROM 大小需在 ISP 下载时设置。

[3] Keil. *C251 Compiler / A251 Assembler / L251 Linker User's Guide*.
`INTVECTOR` 编译器控制、`CLASSES` 链接器控制、`RomSize` 与 near/far 代码
寻址的关系。

[4] 项目内部记录：`/memories/repo/keil-c251.md`，含更细粒度的踩坑条目与实测数据。

---

## 10. 未完成工作

- **蓝牙链路实测**。协议层对物理层无假设，理论上无需改动，但未验证。
  重点关注两段波特率切换在蓝牙链路上的处理（见 §2.2），以及丢包率对 243 块
  传输的影响、是否需要调整重试次数与超时。
- **断电中断测试**。传输过程中断开链路，验证 bootloader 依据"App 首字节非
  `0x02`"判定失败并停留在下载模式。机制上应当成立（§5.1），但未实测。
- **连续多次升级压力测试**。目前最多验证连续两次。
- **`codegen_debug.gd` 的 `Channal` 定义**。`nrf24l01.h` 通过 `extern uint8_t Channal`
  引用它，其余三个生成器（infantry/engineer/engineer_ik）均已包含定义，唯独
  调试生成器（引脚自检）缺少，使用调试生成器的产物将链接失败。该生成器不参与
  日常编译路径，优先级较低。

---

## 11. 附录：已弃用的自研协议

项目早期自研过一套 bootloader（`stc32g/Projects/BOOTLOADER`），采用
`AA 55 | ver | cmd | addr(3) | len(2) | payload | crc16(2)` 帧格式与独立的
元数据扇区方案，配套 `iap_proto.c` / `iap_proto.h` 提供 CRC-16/MODBUS 实现。

该方案被弃用的原因是其地址布局假设 App 能链接到 `0xFF2000`，但实测改 uvproj 的
`<IROM>`/`<Cpu>`/`<CClasses>` 都不会进链接器（生成的 `.lnp` 始终只有
`CLASSES (EDATA..., HDATA...)`），方案不成立。正解是官方例程的
`INTVECTOR(0x1000)` + `isr.asm` 蹦床 + 上位机搬复位向量三者配合
（见 §4），替代实现在 `stc32g/Projects/PIE_BOOTLOADER`。

弃用后保留的有价值产物：

- `stc32g/Libraries/deivers/src/iap_proto.c` 的 `iap_crc16()` / `iap_crc16_update()`
  -- 在 `IAP_PROBE` 探针上验证过与 PC 侧逐位一致，留作未来协议演进的储备
- `stc32g/Projects/BOOTLOADER/USER/src/main.c` 中直接操作 IAP 寄存器并检查
  `CMD_FAIL` 的原语（库函数 `EEPROM_*` 不检查 `CMD_FAIL`，不能用）
- `scripts/test_iap_proto.gd` 的 CRC-16 交叉验证与地址边界断言

`stc32g/Projects/BOOTLOADER/USER/src/main.c` 顶部已注明"已弃用，保留作参考"，
勿照此实施。

---

## 附录 A：文件清单

### 芯片侧

```
stc32g/Projects/PIE_BOOTLOADER/
  USER/src/  main.c  dfu.c  iap.c  uart.c  isr.asm
  USER/inc/  config.h  dfu.h  iap.h  uart.h  stc.h  stc32g.h
  MDK/Project_Template.uvproj
  dist/pie_bootloader.hex     出厂烧录用，随套件分发
  dist/README.md              烧录参数说明
```

相对官方参考实现的改动仅三类：主频、引脚、§7.4/§7.6 的缺陷修复。其余源码保持
原样，以便继续与官方比对。

### 上位机侧

```
stc32g/toolchain/stcflash/
  pie_block_iap.py        协议实现、下载流程、hex 校验、脱机自测（--selftest）
  bootloader_probe.py     单命令探针，用于快速确认 bootloader 在线
  check_hex_layout.py     hex 地址布局核对，支持两个 hex 的字节级比对
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

`scripts/codegen/codegen_base.gd` 的 `_gen_isp_monitor()` 生成 App 侧的 `DfuFlag`
声明、`iapEnterDownload()` 函数与主循环兜底检查；四个 App 项目的 `isr.c` 负责
在 UART1 中断中匹配 `@PIEIAP#` 命令字并在 ISR 内立即进入 bootloader。

---

## 附录 B：维护提示

**修改 `LDR_SIZE` 须三处同步**：`config.h`、`isr.asm` 的 `LDR_SIZE EQU`、
所有 App uvproj 的 `INTVECTOR(...)`。遗漏任一处的表现为 App 静默不启动。

**修改协议须运行自测**：`python pie_block_iap.py --selftest`。其中包含由真机
抓包固化的断言，改动引入不一致时会立即暴露。

**修改 uvproj 后须核对 hex**：`python check_hex_layout.py <hex>`，
确认 `app entry` 报告"空洞(待搬入)"且 `0xFF0000` 处仅有 3 字节。链接器 CODE
起点变更后还要确认 `0xFF1003`–`0xFF11FF` 向量表区未被普通段挤占。

**批量验证多个固件变体须使用 `-r` 而非 `-b`**：Keil 的 `-b` 会跳过重新编译，
导致多个不同变体报告完全相同的 Program Size。判别依据为不同构型的 code/xdata
尺寸必须互不相同。

**更换蓝牙模块须核对波特率**：bootloader 的 `BAUD` 在编译期写死
（当前 230400，由 `config.h` 的 `FOSC` 推导）。旧 115200 bootloader 需要
通过官方 STC-ISP 物理升级，新版 USB 与蓝牙链路均固定使用 230400。

**修改 uvproj 或库文件须同时改 `PROJECT_VERSION`**：位于
`scripts/toolchain.gd`。该常量不变时已运行过的用户那里 `user://` 不会更新，
他们会用旧配置编译且无任何提示。此问题实际发生过：给四个 App 打完
bootloader 共存配置后 `user://` 仍为旧版，表现为下载时报
"0xFF1000 已被占用"，错误信息距真因很远。

**App 与 bootloader 波特率有三处必须一致**：`codegen_base.gd` 的 `APP_BAUD`、
`toolchain.gd` 的 `DEFAULT_APP_BAUD`、`pie_block_iap.py` 的 `DEFAULT_APP_BAUD`。
不一致时 App 收不到触发字，现象却是"bootloader 没有响应"，离真因很远。
`test_download_conn.gd` 有断言守着这个约束。

**在项目目录内放 Keil 产物须加 `.gdignore`**：Keil 的目标文件扩展名是
`.obj`，与 Wavefront OBJ 同名，Godot 会把它当 3D 模型按文本解析，
刷出上百行 `Unicode parsing error` 并报
`resource_importer_obj.cpp:691 Condition "meshes.size() != 1" is true`。
`stc32g/` 下已有 `.gdignore`，但解压官方例程一类临时目录需要自行添加。
注意 `.gitignore` 与 `.gdignore` 是两套互不相干的机制 -- 前者管版本控制，
后者管资源导入，都要写。
