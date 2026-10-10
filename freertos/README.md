# FreeRTOS STC32G12K128（SDCC MCS-251 移植）

本目录是 STC 官方 FreeRTOS 演示（内核 V10.4.6，STC 移植版 V1.0.2）向
**SDCC MCS-251** 的移植结果。原来的 Keil C251 工程文件、Keil 专有库与
USB CDC 示例已移除，源码与构建脚本现在只用仓库内置的 SDCC 工具链。

> 目标编译器：`sdcc -mmcs251`（SDCC 4.6.0，ABI revision 2）。
> 目标芯片：STC32G12K128，24 MHz 系统时钟，1 ms 系统节拍。
> 代码布局：LARGE（复位/中断向量在 `0xFF0000`，全部代码在 64 KB 窗口内）。

## 构建

先准备工具链（以下命令在仓库根目录执行；仓库内已暂存了可用的 Linux 工具链）：

```bash
./tools/prepare_sdcc_toolchain.sh        # 首次或需要重建时，产出 vendor/sdcc-toolchain
```

然后构建固件：

```bash
./freertos/build.sh
```

等价 PowerShell 入口（与 `stc32g_sdcc/build.ps1` 风格一致，本仓库未在
Linux 环境验证 pwsh）：

```powershell
pwsh .\freertos\build.ps1
```

常用参数与环境变量：

```bash
./build.sh --sdcc /path/to/sdcc \
           --lib-dir /path/to/mcs251-large-stack-auto \
           --std-include /path/to/sdcc/include \
           --output /tmp/freertos-build

SDCC=... SDCC_LIB_DIR=... SDCC_INCLUDE_DIR=... ./build.sh
```

产物位于 `freertos/build/FREERTOS_DEMO/`：

| 文件 | 说明 |
|---|---|
| `FREERTOS_DEMO.hex` | 可烧录的 Intel HEX |
| `FREERTOS_DEMO.map` | 链接 MAP，含各段与符号地址 |
| `generated_interrupt_declarations.h` | 构建脚本扫描 `__interrupt()` 定义后生成的声明头 |

每次链接后都会执行 `tools/check_layout.py` 校验布局，失败即构建失败。

运行端口契约测试：

```bash
./freertos/tests/run_tests.sh
```

## 内存布局

| 区域 | 地址 | 说明 |
|---|---|---|
| 复位/中断向量 `HOME` | `0xFF0000` | 复位槽 3 字节 `LJMP`，其余每中断槽 8 字节 `EJMP` |
| 应用代码 `GSINIT*/CSEG/XINIT` | `0xFF0000`–`0xFFFFFF` | 与 Keil LARGE 模式一致，总长须 ≤ 64 KB |
| XRAM `XSEG/XISEG` | `0x010000`–`0x012000` | 8 KB 片内 XRAM |
| edata `DSEG/SSEG/BSEG/BIT_BANK/REG_BANK_0` | `0x0000`–`0x03FF` | 直接寻址数据与启动栈 |
| FreeRTOS 堆 `FRHEAP` | `0x0400`–`0x0FFF` | 3072 B，由 `-Wl-b FRHEAP=0x0400` 钉住 |

FreeRTOS 任务栈必须落在硬件栈指针 `SPX` 可寻址的 region `00:`（片内 edata）。
SDCC MCS-251 没有可用的 edata 存储类（`__data`/`__near` 是 8 位页零指针），
因此 `portheap.asm` 把堆定义成一个 `XDATA` 类型区域，再用链接参数钉到
edata `0x0400`：C 侧按 xdata 经 `DPX` 访问，物理地址就是 `00:0400`，
`heap_4.c` 分配出的 TCB/任务栈因此天然位于 region `00:`。

## 上下文切换

- `vTickISR()` 声明为 `__interrupt (1)`，既是系统节拍也是唯一的任务切换点。
  SDCC 会为“调用其它函数的 ISR”生成完整寄存器保存：
  `push bits,acc,b,dpl,dph,r15..r8,r7..r0,psw`，返回前反向 `pop` 并 `RETI`。
- 端口只保存/恢复 `SPX`（SFR `SPH:SP`）到 `pxCurrentTCB->pxTopOfStack`。
- `portYIELD()` 不直接切换，而是把 `TF0` 置位软件触发 Timer0 中断，复用同一
  套任务帧；中断关闭时挂起的 `TF0` 会在开中断后生效。
- 首个任务由 `xPortStartScheduler()` 按同一帧布局手工构造（23 字节，见
  `Sources/FreeRTOS/portable/STC32G12K128/portasm.h`），弹出寄存器后 `ERET`
  进入任务；`pvParameters` 按 ABI 放在 `B:DPH:DPL`。

`tests/test_port_frame.py` 会从 `sdcc -S` 产物中提取真实的序言/尾声，逐项与
端口帧对齐，防止升级工具链后静默破坏上下文切换。

## 与 Keil 版的主要差异

1. **端口层重写**：`port.c`/`portmacro.h`/`portasm.h` 改为 SDCC MCS-251
   （3 字节平坦指针、`ECALL/ERET`、`__interrupt()`、`__data/__code`）。
2. **USB CDC 移除**：`usb_cdc.c` 依赖 Keil OMF251 库
   `stc_usb_cdc_32g.LIB`，SDCC 无法链接，仓库内也没有等价的 C 源码；
   `main.c` 已删除 USB_CDC 任务，其余 6 个演示任务保留。
3. **精简 FreeRTOS 特性**：实测原配置（任务通知 + 互斥量 + 32 优先级）
   仅内核就 60 586 B，加上演示任务会超出 64 KB LARGE 窗口。因此关闭本演示
   未使用的 `configUSE_TASK_NOTIFICATIONS`、`configUSE_MUTEXES`、
   `configUSE_COUNTING_SEMAPHORES`、`configUSE_TIMERS`，并把
   `configMAX_PRIORITIES` 降为 8（演示最高只用到 3）。当前镜像约 50 KB。
   如需启用这些特性，请另做 128 KB HUGE 代码布局。
4. **堆与栈尺寸**：`configTOTAL_HEAP_SIZE` 3072 B，配合
   `configMINIMAL_STACK_SIZE`/`configDEFAULT_STACK_SIZE` 均取 256 B。
5. **删除 Keil 工程**：`.uvproj/.uvopt/keilclean.bat`、`Objects/`、
   `Listings/`、Keil 寄存器头 `STC32G.H` 与 Keil 专有文件均已删除；SDCC
   寄存器头复用 `stc32g_sdcc/include/STC32Gxx.h`（见构建清单）。

## 已知限制

- **未做真机/QEMU 运行验证**：本仓库环境没有 STC32G 硬件，也没有
  `qemu-system-mcs251`。已验证的是编译、链接、布局与帧序契约；上电行为需
  按下面的清单在真机复核。
- **少记一拍 tick**：`portYIELD()` 用置位 `TF0` 触发切换，若恰好与真实定时器
  溢出同时发生，会合并成一次中断而少记一拍。概率极小、影响有界。
- **临界区不可嵌套**：沿用 STC 官方 Keil 端口的 `EA = 0/1` 语义，不维护嵌套
  计数；如需嵌套需在端口层补充按任务保存的计数。
- **仅 STC32G12K128 / 24 MHz / 1 kHz tick**：换频率需同步修改
  `MAIN_Fosc`；换芯片需重新核对 edata/XRAM 布局与链接参数。
- 演示任务（数码管/ADC 按键/NTC/软件 RTC/UART2-3/矩阵按键/串口 printf）按
  原 Keil 逻辑平移，未做功能变更。

## 真机复核清单（建议）

1. 烧录 `build/FREERTOS_DEMO/FREERTOS_DEMO.hex`，确认数码管按秒闪烁、
   显示时间走时。
2. 用示波器测 P35/P36 或任意任务输出，确认 1 ms 节拍与任务切换正常。
3. 串口 115200 连接 UART1，打开 `DebugPrintfInit()` 后确认 `printf` 输出。
4. 通过 ADC 按键/UART2/矩阵按键触发任务，确认多个任务并发无死锁。

## 目录结构

```
freertos/
├── build.sh / build.ps1          构建入口
├── build_manifest.json           源码清单、编译/链接参数与布局常量
├── tools/
│   ├── build_firmware.py         构建驱动（编译、汇编、链接、布局校验）
│   └── check_layout.py           HEX/MAP 布局校验
├── tests/                        端口帧序、源码契约、预算一致性测试
└── Sources/
    ├── FreeRTOS/                 内核（原样）与 STC32G12K128 端口（SDCC）
    │   └── portable/STC32G12K128/port.c, portmacro.h, portasm.h, portheap.asm
    └── User/                     演示任务源码与 SDCC 配置
```

## 版权

FreeRTOS 内核与端口文件遵循 MIT（见各文件头部）；演示任务源码版权归 STC
所有，原声明保留在各文件内。
