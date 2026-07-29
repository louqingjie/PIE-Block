# STC32G12K128 串口 OTA 固件自升级：原理、实现与踩坑记录

面向 pie-block 项目的开发者。读完你应该能回答三个问题：为什么这套机制能工作、
改动哪些配置会让它失效、遇到问题从哪里查。

本文记录的是**已在真机验证通过**的方案。凡是推测性的内容都会明确标注。

---

## 1. 问题背景

pie-block 的用户是做机器人机械结构的大一学生，多数没有编程基础。原来的固件更新
流程是：Godot 生成 `main.c` → Keil 编译 → 打开官方 STC-ISP 软件 → 选型号、配频率、
点下载、给板子上电。对目标用户来说，中间那一大段是纯粹的负担，而且 STC-ISP 的
参数配错了会得到各种难以理解的失败。

目标是让"下载"变成软件里的一个按钮：**串口线不动，程序自己换掉自己**。

这在 ARM 平台上是常规操作，但 STC32G 用的是 MCS-251 内核，它的
Flash 分区、寻址模型、Keil C251 的段管理都和 ARM 生态差别很大，
资料也少。整个过程中最大的困难不是写代码，而是**搞清楚这块芯片到底允许什么**。

---

## 2. 硬件与工具链约束

| 项目 | 值 | 影响 |
|---|---|---|
| 芯片 | STC32G12K128（MCS-251 内核） | 段模型、寻址方式与 8051/ARM 都不同 |
| Flash | 128K | 分区方案的总预算 |
| XRAM | 8K（0x10000-0x11FFF） | 下载标志放在它的末尾 |
| 主频 | 33.1776 MHz | 波特率计算的基准 |
| 编译器 | Keil C251 V5.60 | 段分配行为是本文大量内容的来源 |
| 串口 | CH340，115200 | 唯一的通信通道 |

`33177600 / 4 / 115200 = 72` 整除，所以波特率误差为 0 —— 这一点比官方例程用的
24MHz 还干净，省掉了一类潜在的通信不稳定。

---

## 3. Flash 空间划分

这是整个方案的地基。划分方式取自 STC 官方文档
《利用STC的IAP单片机开发自己的ISP程序-STC32G12K128系列》第 2 页：

```
物理地址
0xFE0000 ┌──────────────────────────┐
         │  低 64K 块区              │  用户代码与数据（不可取指，见 §3.2）
0xFEFFFF └──────────────────────────┘
0xFF0000 ┌──────────────────────────┐
         │  用户 ISP 代码区  4K      │  ← bootloader，出厂烧一次，之后永不改动
0xFF0FFF └──────────────────────────┘
0xFF1000 ┌──────────────────────────┐
         │  用户 AP 代码区  60K      │  ← App 入口、中断向量、启动代码
0xFFFFFF └──────────────────────────┘
```

### 3.1 IAP 地址与物理地址的换算

IAP 操作用 `IAP_ADDRE/ADDRH/ADDRL` 三个寄存器寻址，但 `IAP_ADDRE` 只取 bit16
（芯片侧代码里是 `IAP_ADDRE = BYTE2(addr) & 0x01`），所以 IAP 地址空间是 17 位：

```
IAP 地址 = 物理地址 & 0x1FFFF
```

- IAP `0x00000-0x0FFFF` ↔ 物理 `0xFE0000-0xFEFFFF`
- IAP `0x10000-0x10FFF` ↔ 物理 `0xFF0000-0xFF0FFF`（bootloader，禁止写）
- IAP `0x11000-0x1FFFF` ↔ 物理 `0xFF1000-0xFFFFFF`

就是一次按位与，没有偏移。这一点我曾误判过（见 §7.1）。

### 3.2 关键约束：低 64K 区不能取指执行

Phase 0 的探针（`stc32g/Projects/IAP_PROBE`）实测：把一小段位置无关代码拷到
`0xFE0000` 再通过 far 指针调用，**芯片立即复位**。XRAM 执行同样复位。

这个事实曾让我误判整个方案不可行（§7.2）。实际含义要精确表述：

> `0xFE0000` 区不能作为**取指入口**，但那里的代码可以通过 far 调用正常执行。

区别在于程序的入口与中断向量必须落在 `0xFF1000` 之后 —— 剩下的绝大部分函数体
放在低 64K 完全没问题。真机验证的 App 有 30103 字节代码全在 `0xFE0000`，运行正常。

---

## 4. 让 App 跑在 0xFF1000：五项配合

这是全篇最容易出错的地方。**五项缺一不可**，而且失效时大多不报错，只是行为异常。

### 4.1 bootloader 侧：`isr.asm` 中断蹦床

MCS-251 的中断入口地址是硬件固定的（`0x0003`、`0x000B`、每 8 字节一个），
而那些地址落在 bootloader 的 4K 里。官方的解法是在 bootloader 里放 67 条转发指令：

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

每个中断入口放一条 `LJMP` 跳到 `原地址 + 0x1000`。移植时**必须带上 isr.asm**，
漏掉的话 App 的所有中断都会失效 —— 而且不报编译错误。

### 4.2 App 侧：`RomSize` = 4

**这一项是整个方案的关键，也是我卡了两轮的地方。**

它决定代码走 near(`CODE`) 还是 far(`ECODE`) 寻址。不改的话所有函数都编进 `CODE` 类，
而 **`CODE` 类的基址恒为 `0xFF0000` 且改不动** —— 这才是"Keil 不让改代码基址"的
真正原因。改成 4 之后代码自然落进 `ECODE (0xFE0000-0xFFFFFF)`。

代价是 code 体积涨约 4%（far 调用指令更长），实测 25563 → 26572 字节。

### 4.3 App 侧：`Ocm1` 段激活

```xml
<Ocm1>
  <Type>1</Type>                        <!-- 必须是 1 -->
  <StartAddress>0xfe0000</StartAddress>
  <Size>0x20000</Size>
</Ocm1>
```

`Type` 必须改成 1。只改地址和大小的话整段被忽略，生成的 `.lnp` 里根本不会出现
`ECODE` —— 我第一次就踩在这里，改完看着没生效还以为方向错了。

### 4.4 App 侧：编译器选项 `INTVECTOR(0x1000)`

位置是 uvproj 的 `<C251><VariousControls><MiscControls>`。

它把中断向量表推到偏移 `0x1000`，与 §4.1 的蹦床对齐。注意**它只挪中断向量，
不挪代码基址** —— 我最初以为一个选项能解决全部问题，结果第一次编译出来
App 代码照样占满整个 4K bootloader 区。

这是个**编译器**选项而不是链接器选项。前两轮我一直在链接器配置里找，方向就错了。

### 4.5 App 侧：链接器 `CLASSES (CODE (0xFF1003-0xFFFFFF))`

位置是 uvproj 的 `<Lx51><MiscControls>`。两个作用：

1. 把 `CODE` 类起点抬出 bootloader 的 4K。只挪向量表不够 —— 启动代码
   `?C_C51STARTUP` 等段仍会填进 `0xFF0003` 起的空间。
2. 给上位机搬复位向量留出 `0xFF1000-0xFF1002`。

**起点必须是 `0xFF1003` 而不是 `0xFF1000`。** 设成 `0xFF1000` 时链接器会把
`?CO?MAIN` 段（内含 `"@PIEIAP#"` 命令字常量）正好放在那里，搬运复位向量会覆盖
命令字的前 3 字节，App 从此认不出下载指令。官方例程没暴露这个问题只是因为它的
`0xFF1000` 恰好空着 —— 段分配随编译结果变化，不能依赖。

### 4.6 App 侧：`HexSelection` = 1

bootloader 用 0（只输出 `CODE` 段），App 必须用 1，否则 `ECODE` 段的代码
**不会写进 hex**。这个失效特别隐蔽：`code=301` 但 hex 只有 48 字节，不报任何错。

### 4.7 上位机侧：搬运复位向量

App hex 里 `0xFF0000-0xFF0002` 有 3 字节 `LJMP`，要搬到 `0xFF1000-0xFF1002`。
理由有两条：

- bootloader 占着 `0xFF0000-0xFF0FFF`，IAP 会拒绝写那里
- bootloader 跳转前要检查 `*(BYTE code *)(LDR_SIZE) == 0x02`，
  即物理 `0xFF1000` 处必须是 LJMP 指令

官方 PDF 原话："重映射的工作上位机应用程序会自动处理，用户在编写 AP 代码时
无需关心"。实现在 `pie_block_iap.py` 的 `relocate_reset_vector()`。

### 4.8 配置正确后的 hex 布局

```
0xFE0000 起        用户代码（实测 24736-30209 字节）
0xFF0000-0xFF0002  3 字节 02 10 A7 = LJMP 0x10A7
0xFF0003-0xFF0FFF  空 → bootloader 安全
0xFF1000-0xFF1002  空洞 → 待上位机搬入
0xFF1003 起        命令字 + 中断向量 + 启动代码
```

核对工具：`python check_hex_layout.py <hex>`，看 `app entry` 是否报"空洞(待搬入)"。

---

## 5. 运行时流程

### 5.1 启动判断

bootloader 上电后做四重校验，全部通过才跳 App：

```c
if ((DFU_FORCEPIN != 0) &&                          /* 引脚未被拉低 */
    (DfuFlag != DFU_TAG) &&                         /* 无下载标志 */
    (*(BYTE code *)(LDR_SIZE) == 0x02) &&           /* App 首字节是 LJMP */
    (*(WORD code *)(LDR_SIZE + 1) >= LDR_SIZE + 3)) /* 跳转目标跨过本区 */
{
    ((void (far *)())(0xff0000 + LDR_SIZE))();
}
```

第三、四重校验同时充当**断电保护**：下载中途掉电时 App 首字节不是 `0x02`，
bootloader 会停在下载模式等重下，不会跳进半截固件。这比自己维护元数据扇区
更省空间也更可靠。

### 5.2 下载标志放 XRAM 而非 Flash

```c
DWORD xdata DfuFlag _at_ 0x1ffc;   /* XRAM 末尾 4 字节 */
```

软复位不清零 XRAM，所以 App 写完标志再复位，bootloader 还能读到。

这个设计比我原本打算的"擦一个元数据扇区"好得多：不动 Flash，
没有擦写磨损，也没有"标志写一半掉电"的风险。App 侧只需两行：

```c
DfuFlag = 0x12abcd34;
IAP_CONTR = 0x20;      /* SWRST=1, SWBS=0 → 复位到用户程序 */
```

`IAP_CONTR = 0x20` 是复位到**用户程序**（也就是 bootloader），
而不是 `0x60` 那样进 ROM ISP。这绕开了 ROM ISP 对 IRC trim 和
2400 波特率握手的依赖，那是旧方案不稳定的根源。

### 5.3 完整时序

```
PC 发 @PIEIAP#
  └─ App 的 UART1 ISR 匹配命令字，置 iapDownloadReq
     └─ App 主循环写 DfuFlag，IAP_CONTR = 0x20
        └─ 芯片复位 → bootloader 启动
           └─ 读到 DfuFlag == DFU_TAG，停在下载模式
              ├─ CONNECT  → 回版本号 0x0100
              ├─ ERASE    → 擦 App 区（bootloader 自身受保护）
              ├─ PROGRAM  → 分块写入
              ├─ READ     → 读回校验
              └─ REBOOT   → IAP_CONTR = 0x20，跳新 App
```

### 5.4 地址保护

保护写在 IAP 最底层，所有调用路径自动覆盖：

```c
BOOL iap_check_addr(DWORD addr)
{
    addr &= 0x1ffff;
    return ((addr < 0x10000) || (addr >= (0x10000 + LDR_SIZE)));
}
```

拒绝 IAP `0x10000-0x10FFF`，正是 bootloader 自己那 4K。真机验证过：
ERASE 命令从 `0x00000` 一路擦到 `0x1FFFF`，走完全程后 bootloader 仍能应答。

### 5.5 硬件逃生通道

**P32 拉低再上电** → 第一重校验不成立 → 无条件停在下载模式。

用户程序跑飞、串口被占死时靠这个救回来。真机验证 5/5 应答。

官方例程用 P33，我们改 P32 —— P33 在本项目是蜂鸣器。P3 口占用情况：
P30/P31 串口、P33 蜂鸣器、P34 遥控器复位、P37 状态灯，只有 P32 空闲。

---

## 6. 通信协议

沿用官方帧格式，好处是调试期可以拿官方 `StcIsp_User.exe` 交叉对照。

```
主机 → 芯片:  '#' | len | cmd | payload... | '$' | 累加和
芯片 → 主机:  '@' | status | size | payload... | '$' | 累加和
```

- `len` = cmd 加 payload 的字节数
- 累加和 = 使整帧字节之和的低 8 位归零的那个字节

| 命令 | 值 | payload |
|---|---|---|
| CONNECT | 0xA0 | 无，回 2 字节版本号 |
| READ | 0xA1 | addr(4,小端) + size(1) |
| PROGRAM | 0xA2 | addr(4,小端) + size(1) + data |
| ERASE | 0xA3 | 无 |
| REBOOT | 0xA4 | 无，不回应 |

状态码：`OK=0` / `ERRORCMD=1` / `OUTOFRANGE=2` / `PROGRAMERR=3` / `ERRORWRAP=0xFF`

`pie_block_iap.py` 的自测里把真机抓到的帧字节序列写成了断言：

```python
check("CONNECT 帧", build_frame(CMD_CONNECT).hex(), "2301a02418")
check("ERASE 帧",   build_frame(CMD_ERASE).hex(),   "2301a32415")
check("REBOOT 帧",  build_frame(CMD_REBOOT).hex(),  "2301a42414")
```

以后改协议时这几行必须仍然相等，否则芯片侧就对不上了。

---

## 7. 实现历程：四次错误判断

这一节记录走过的弯路。留着它是因为这些错误都有共同的模式，值得复盘。

### 7.1 误判一：以为 IAP 地址与 hex 地址差 0x1000

我把 `LDR_SIZE` 在两个语境的用法搞混了：它既是 code 空间的偏移量，
又出现在 IAP 地址计算里。于是推断"hex 偏移与 IAP 地址相差 0x1000，
需要抓包确认"。

实际上换算就是 `iap_addr = phys_addr & 0x1FFFF`，没有偏移。
读官方 PDF 第 2 页的分区图 + 实测解析两个 hex 就定论了，不需要抓包。

**教训**：同一个常量出现在不同语境时要显式区分，别指望靠记忆保持一致。

### 7.2 误判二：认为 App 无处可放，方案不可行

探针 Q6 实测 `0xFE0000` 区"调用即复位"，Q7 实测 XRAM 也一样。我从这两个
事实推出"App 无处可放"，甚至一度转向研究字节码解释器方案。

结论本身没错，但**适用范围被我放大了**：不能取指指的是不能作为入口，
不代表那里的代码不能通过 far 调用执行。官方答案是放在同一代码区的偏移处
`0xFF1000`，函数体则留在低 64K。

**教训**：实测结论要精确表述边界。"不能执行"和"不能作为入口"是两回事，
含糊的表述会在后续推理里被放大成错误结论。

### 7.3 误判三：三轮找错了配置项

前两轮我一直改 uvproj 的 `<IROM>`、`<Cpu>`、`<CClasses>` 想挪代码基址，
全部无效 —— 生成的 `.lnp` 里始终只有 `CLASSES (EDATA..., HDATA...)`。
（原因后来才知道：`UseMemoryFromTarget=1` 时 `<CClasses>` 被忽略。）

真正的答案是 `RomSize` 3→4 加 `INTVECTOR` 编译器选项。**我一直在链接器配置里
找一个编译器选项。**

这一轮浪费的时间最多，直到下载官方例程逐项 diff 才定位。

**教训**：同类尝试连续失败两次之后，应该停下来找权威参考，而不是继续在
同一个配置区域里试排列组合。官方例程一直挂在 stcai.com 上，早看能省两轮。

### 7.4 误判四：取样有偏导致连续两次错误修复

真机 PROGRAM 失败。我测了 payload 长度 1/2/4/16/64/128，结果"只有 1 成功"。
于是推断是回读校验的时序问题，改了两次：

1. 加 `iap_verify_byte()` 走 IAP 读来回读 —— 无效
2. 干脆去掉逐字节回读 —— 无效

两次都白改，还各让用户重烧一次板子。

后来把 1..24 全扫一遍，才看到真实规律是**严格的奇偶交替**。
那种整齐度只可能来自确定性的逻辑错误，不可能是时序。

根因在 map 文件里：

```
00000021H   EDATA    UartRxBuffer
```

`UartRxBuffer` 落在 `0x21` **奇地址**，于是 `UartRxBuffer[2]` 在 `0x23` 也是奇地址。
官方代码 `addr = *(DWORD *)&UartRxBuffer[2]` 是**从奇地址做 32 位读**，
MCS-251 按对齐边界取字，拿到错位的字节组合。改成逐字节拼装即解决。

**教训**：
- 我最初测的六个长度里除了 1 全是偶数，这个偏差直接导致误判。
  规律"太整齐"时应该先怀疑取样，而不是急着解释。
- 中途还有一次二级误判：我的 `request()` 重试三次后抛"写入失败"，
  我盯着自己包装的错误信息看，以为都是 `PROGRAM_ERR`，实际有些是根本没回应。
  **看原始字节比看封装后的错误信息可靠。**

### 7.5 顺带修的两个官方缺陷

**`dfu.c` 的 `UartInBuffer`**：DEBUG 分支里引用了一个不存在的变量。
因为那段代码从未被编译过，笔误一直留着。应为 `UartTxBuffer`。

**`dfu.c` 的引脚掩码**：`DFU_FORCEPIN` 定义在 `dfu.h`，但 `dfu.c` 里
把 P33 的掩码 `0x08` 硬编码了三处。只改头文件的话上拉会配到蜂鸣器引脚上，
逃生通道失效，且不报错。已抽成 `DFU_FORCEPIN_MASK`。

---

## 8. 真机验证结果

### 8.1 移植正确性

**移植刚完成时**（提交 `bf79a91`，只改了主频与引脚，尚未修 bug），
编译产物 927 字节，与官方例程做字节级 diff **只差 7 字节**，
且每一处都能对应到明确的改动：

| 地址 | 我们 | 官方 | 对应 |
|---|---|---|---|
| 0x2B0 | FB | F7 | `~0x04` vs `~0x08` |
| 0x2BD/0x2FF/0x310 | 04 | 08 | 引脚掩码 |
| 0x2C9 | B2 | B3 | 位寻址 P32 vs P33 |
| 0x465/0x4D8 | — | — | BAUD 65484 → 65464 |

这个手法比"编译通过"强得多 —— 它能证明没有意外的副作用。移植这类工作
值得专门做一次这样的对比。

**当前版本**（997 字节）与官方差 706 字节，因为后来修了 §7.4/§7.5 的三处 bug
并启用了 `DEBUG`（READ 命令），代码结构已经变了。所以字节级 diff 只适用于
移植验证阶段，之后要靠功能测试。

### 8.2 OTA 端到端

连续两次 OTA，全程只用串口，不碰硬件：

| | 第一版 | 第二版 |
|---|---|---|
| 每次连发 | 60 字节 | 10 字节 |
| 闪烁周期 | 502 ms | 100.5 ms |
| 实测间隔 | 502/503/502/502 | 101/100/100/101/100 |

节奏精确变成源码里写的值。演示固件的延时完全依赖定时器 0 中断累加计数，
中断进不来就会死等 —— 所以这个数字同时验证了中断蹦床生效。

30KB 的正式固件也下载成功：30252 字节切成 243 块，全部读回校验通过。

### 8.3 各项验证清单

| 项目 | 状态 | 依据 |
|---|---|---|
| bootloader ≤ 4K | 通过 | 997 字节 |
| 中断蹦床 | 通过 | hex 里 64/67 入口指向 +0x1000（官方同为 64/67）|
| 与官方一致性 | 通过 | 字节级 diff 仅 7 处 |
| CONNECT | 通过 | 回版本号 0x0100 |
| ERASE + 自我保护 | 通过 | 擦完全程后仍能应答 |
| PROGRAM 各长度 | 通过 | 1..24 字节全部写入正确 |
| READ | 通过 | 读 IAP 0x10000 得到 bootloader 自身代码 |
| 30KB 固件下载 | 通过 | 243 块读回校验全过 |
| ECODE 区可执行 | 通过 | 用户代码全在 0xFE0000，运行正常 |
| 中断转发到 App | 通过 | 定时器延时实测 100.5/502 ms |
| App 侧触发链路 | 通过 | 第二次 OTA 靠它进入 bootloader |
| P32 逃生通道 | 通过 | 5/5 应答 |
| 断电中断保护 | **未测** | 仅代码层面推理，见 §10 |

---

## 9. 文件清单

### 芯片侧

```
stc32g/Projects/PIE_BOOTLOADER/
  USER/src/  main.c dfu.c iap.c uart.c isr.asm
  USER/inc/  config.h dfu.h iap.h uart.h stc.h stc32g.h
  MDK/Project_Template.uvproj
  dist/pie_bootloader.hex     ← 出厂烧录用，随套件分发
  dist/README.md              ← 烧录参数说明
```

改动相对官方例程只有三类：主频、引脚、§7.4/§7.5 的三处 bug 修复。
其余源码保持原样，方便继续与官方 diff。

### PC 侧

```
stc32g/toolchain/stcflash/
  pie_block_iap.py        协议实现 + 下载流程 + 脱机自测（--selftest）
  bootloader_probe.py     单命令探针，用于快速验证 bootloader 是否在线
  check_hex_layout.py     hex 地址布局核对，支持两个 hex 字节级 diff
```

### 代码生成

`scripts/codegen/codegen_base.gd` 的 `_gen_isp_monitor()` 生成 App 侧的
`DfuFlag` 声明与触发函数。四个 App 项目的 `isr.c` 负责在 UART 中断里匹配命令字。

---

## 10. 已知未完成项

- **断电中断测试未做**。PROGRAM 中途拔串口，确认 bootloader 靠"App 首字节非
  0x02"判定失败并停在下载模式。机制上应该成立（§5.1），但没实测过。
- **未接入 Godot UI**。目前只能命令行调用 `pie_block_iap.py`。
  `scripts/toolchain.gd` 里的 `download_hex_iap()` 还是旧协议，需要重写。
- **`codegen_debug.gd` 缺 `Channal` 定义**，而 `nrf24l01.c` 通过 extern 引用它，
  用调试生成器的产物会链接失败。其余三个生成器都有这一行。
- **连续多次下载未做压力测试**。目前最多连续两次。

---

## 11. 参考资料

1. STC《利用STC的IAP单片机开发自己的ISP程序 —— 基于STC32G12K128》
   官方例程包 `STC-official-user-UART-ISP-bootloader-demo-STC32G12K128-series.zip`，
   来源 stcai.com「做自己的升级软件」页。含 PDF、bootloader 源码、Demo App、
   PC 端上位机。**本方案的主要依据，遇到疑问优先查它。**
2. STC32G 系列技术手册。第 905 页 `IAP_CONTR` 寄存器位定义（`CMD_FAIL` 在 B4）；
   第 906 页 EEPROM 大小需在 ISP 下载时设置。
3. Keil C251 编译器/链接器手册。`INTVECTOR` 编译器控制、`CLASSES` 链接器控制、
   `RomSize` 与 near/far 代码寻址的关系。
4. 项目内记录：`/memories/repo/keil-c251.md` 有更细的踩坑条目与实测数据。

---

## 12. 维护提示

**改 `LDR_SIZE` 要三处同步**：`config.h`、`isr.asm` 的 `LDR_SIZE EQU`、
所有 App uvproj 的 `INTVECTOR(...)`。漏一处的表现是 App 静默不启动。

**改协议要跑自测**：`python pie_block_iap.py --selftest`。里面有真机抓包
写成的断言，改坏了会立刻发现。

**改 uvproj 后核对 hex**：`python check_hex_layout.py <hex>`，
确认 `app entry` 报"空洞(待搬入)"且 `0xFF0000` 只有 3 字节。

**批量验证多个固件变体时用 `-r` 而不是 `-b`**：Keil 的 `-b` 会跳过重编译，
几个完全不同的变体可能报出一模一样的 Program Size。判据是不同构型的
code/xdata 尺寸必须各不相同。
