# SDCC mcs251 中断不保存 DPXL 导致 ROMOVF 复位循环

## 现象

STC32G12K128 车体板跑调试台固件时，蜂鸣器不断重复"初始化提示音"，
串口反复出现启动横幅与：

```text
ev=RESET rst=ROV boot=2 raw=0x06 flags=ROV+SW pcon=0x20 wdt=0x07 rstcfg=0x50
```

- `rst=ROV`（ROMOVF，CPU 执行到非程序区）、`flags=ROV+SW`
- `wdt=0x07` 的 EN_WDT=0，看门狗并没有使能，`rstcfg` 无异常 → 不是看门狗/复位脚/低压
- `boot` 序号在 ~90 秒内从 1 涨到 90+，说明是复位循环而不是 PWM 停在发声状态
- 串口日志里还夹着坏字符（`moe=RX`、`bui` 丢失、行首错位）

## 根因

1. **SDCC mcs251 的 `__interrupt` 序言只保存 `dpl`/`dph`，不保存 `dpxl`。**
   见 `sdcc-c251/src/mcs251/gen.c` 中 ISR 序言生成处（注释即
   "save acc, b, dpl, dph"）。`dpxl` 是 MCS-251 的 24 位指针高字节
   （SFR 0x84），主循环里所有 `__code` 字符串读取、`switch` 跳表取址都要用它。
   中断落在 `mov dpxl,#...` 与后续 `movc`/`movx` 之间时，ISR 内对 XDATA 的访问
   会把 DPXL 改掉，返回后取到错误页地址——字符串读出坏字符，跳表则取到错误
   跳转目标。

2. **主循环热路径里的 `switch` 被编译成 3 字节跳表 + `ejmp @dr28`。**
   典型是 `CNU_PIE_GPIO.c` 的 `GPIO_Write_Bit()`：nRF 的 CE/CSN 每次收发都会调，
   跳表取址（`movc` → `mov dpxl,a` → `pop dph/dpl` → `ejmp @dr28`）被中断打断时，
   高字节错误 → `ejmp` 跳到非程序区 → **ROMOVF 复位**。

真机日志里 `rst=ROV` 每次复位的时间随机（2~44 s），与"中断恰好落在跳表取址
窗口"的概率特征一致。

## 修复

1. `isr.c`：每个会执行 C 代码的 ISR 在主体外手工保存/恢复 DPXL：

```c
void UART2_Isr(void) __interrupt (8)
{
    __asm
        push dpxl
    __endasm;
    Dbg_UartIsr();
    __asm
        pop dpxl
    __endasm;
}
```

2. 热路径（nRF CE/CSN）不再走 `GPIO_Write_Bit()`，直接用位寻址 SFR：

```c
#define NRF_CE_LOW()  (P34 = 0)
#define NRF_CE_HIGH() (P34 = 1)
#define NRF_CSN_LOW() (P22 = 0)
#define NRF_CSN_HIGH() (P22 = 1)
```

3. 契约测试 `test_dbg_console_contract.py::test_isrs_preserve_dpxl` 守住
   `push dpxl`/`pop dpxl`，防止回退。

## 验证

- 修复前：每 2~12 s（DPXL 修复后仍有每 17~44 s）一次 `ev=RESET rst=ROV`。
- 修复后：连续运行 8 分钟以上，`boot=1` 不再增长，串口输出无坏字符。
- 复现/确认技巧：`build/DBG_CONSOLE/isr.asm` 里搜 `push dpxl`；固件启动行会打印
  `# LAST stage=.. t=.. spmax=..`（保留 XRAM 面包屑）可定位残余跑飞点。

## 上游修复

编译器级修复已提交到上游 PR：
[gevico/sdcc-c251#1](https://github.com/gevico/sdcc-c251/pull/1)
（`mcs251: preserve DPXL and DR28 across interrupts`）——ISR 序言统一
push/pop `DPXL`/`DR28`，只在确实不访问 flat 数据、也不调用函数的 ISR 上由
现有清理逻辑省略；同时新增 `src/mcs251/tests/check-codegen.sh` 回归断言。

合并后重建 `vendor/sdcc-toolchain` 并升级本仓库的 `sdcc-c251` 子模块，
即可删除 `isr.c` 里手工 `push dpxl` 的 workaround。

## 适用范围

仓库里所有 SDCC mcs251 工程都受这条编译器限制影响：**只要 ISR 里访问 XDATA，
就必须手工保存 DPXL**；主循环热路径里的 `switch`（尤其 GPIO 驱动）尽量改成
直接位写或 if 分支，避免 `movc` + `ejmp @dr28` 跳表。
