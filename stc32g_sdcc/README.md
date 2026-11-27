# STC32G12K128 SDCC 工程

此目录包含正式 STC32G12K128 工程的 SDCC MCS-251 迁移副本，以及独立硬件测试工程。原始
`stc32g` 工程和 `STC32G-SOFTWARE-LIB` 独立例程不在本目录的构建范围内。

构建脚本不调用项目代码生成器。需要准备已经构建好的 SDCC MCS-251 工具链和
`large-stack-auto` 运行库；默认从仓库中的 `sdcc-c251` 子仓库查找，也可以通过
参数覆盖路径：

```powershell
pwsh .\stc32g_sdcc\build.ps1 `
  -Project TEST `
  -Sdcc .\path\to\sdcc.exe `
  -LibDir .\path\to\mcs251-large-stack-auto `
  -StdInclude .\sdcc-c251\device\include

pwsh .\stc32g_sdcc\build.ps1 -All -Sdcc .\path\to\sdcc.exe
pwsh .\stc32g_sdcc\build.ps1 -SmokeTest -Sdcc .\path\to\sdcc.exe
```

布局固定为：复位/中断向量 `0xFF0000`，应用代码和常量 `0xFE0000` 起，片内
EDATA `0x0000-0x0FFF`，XRAM `0x010000-0x011FFF`。`tools/check_layout.py`
会在每次链接后检查这些区域以及 SDCC 原生启动符号。应用代码和只读常量都留在
低 64KB，不要依赖 `0xFF1000` 之后的高区：ROM USB-ISP 对高区的擦除/写入不可靠，
多次烧录后可能读到旧数据。

构建时会把共享板级/驱动模块写入工程输出目录的 `stc32g_shared.lib`，由链接器按
引用按需提取，避免未使用的 Keil 工程模块占满代码区。链接器还将 `GSINIT`、用户
代码和只读常量统一放入应用代码区 `CSEG`，并保留 `0xFF0000` 以上的向量空间。

## 最小功能测试与仿真

先运行不需要硬件的主机侧单元测试：

```powershell
pwsh .\stc32g_sdcc\tests\run_unit_tests.ps1
```

测试覆盖步兵底盘混控、死区、摩擦轮安全渐变、扩展板帧编码，以及 SPI/NRF 未
响应时的有限超时。步兵控制和几何/输入语义仍可运行现有 Godot 冒烟测试：

```powershell
godot --headless --path . --script scripts/test_infantry_sim.gd
```

然后构建不依赖遥控器、NRF 或扩展板的最小固件：

```powershell
pwsh .\stc32g_sdcc\tests\build_minimal.ps1 -All `
  -Sdcc .\path\to\sdcc.exe `
  -LibDir .\path\to\mcs251-large-stack-auto
```

`gpio_smoke` 只验证 P35/P36/P37，`uart_smoke` 验证 UART1 的有限发送等待，
`spi_smoke` 验证 SPI 完成位未出现时不会无限阻塞。`qemu_smoke` 可交给
`processmission/qemu` 的 `stc32g144k246`/`stc32g144k246-evb` 模型：

LCD 软件 SPI 可使用独立工程构建，避免 PWM、UART、扩展板和 NRF24L01 干扰：

```powershell
pwsh .\stc32g_sdcc\build.ps1 `
  -Project LCD_SPI_SMOKE `
  -Sdcc .\path\to\sdcc.exe `
  -LibDir .\path\to\mcs251-large-stack-auto
```

该程序使用 `LCD.c` 的 GPIO 模拟 SPI，在屏幕上显示 `LCD SPI OK` 和 `RUN`，
并用 P35 做 250 ms 心跳、P36 表示 LCD 初始化完成。它验证的是 LCD 软件 SPI
和初始化后的持续运行，不验证 `CNU_PIE_SPI.c` 的硬件 SPI。

蜂鸣器音乐测试工程 `BUZZER_MUSIC_SMOKE` 只使用主控板 P33 的 PWM，不启动 NRF
和扩展板通信。测试源由项目音乐模式的代码生成器根据
`projects/BUZZER_MUSIC_SMOKE/music.json` 生成，播放单音阶后循环：

```powershell
$godot = 'C:\path\to\godot.exe'
& $godot --headless --no-header --path . --script scripts/cli_codegen.gd -- `
  generate --kind music `
  --config stc32g_sdcc/projects/BUZZER_MUSIC_SMOKE/music.json `
  --out stc32g_sdcc/projects/BUZZER_MUSIC_SMOKE/src/main.c

pwsh .\stc32g_sdcc\build.ps1 `
  -Project BUZZER_MUSIC_SMOKE `
  -Sdcc .\path\to\sdcc.exe `
  -LibDir .\path\to\mcs251-large-stack-auto
```

#### 音乐固件里的 OLED 五线谱显示

SDCC 音乐工程（`BUZZER_MUSIC_GENERATED` 等）生成的 `main.c` 在 `#if defined(__SDCC)`
分支里带 128×64 五线谱滚动显示：事件/调号/拍号/字形由 `pieblock_core` 预先算好，
固件用 `StaffRender.c`（纯 C，可主机 gcc 编译）绘制，`OLED_Staff.c` 维护 XRAM 帧缓冲，
`LCD_Frame.c` 用软件 SPI 整屏刷新。Keil 构建走 `#else` 分支，保持只播放。

播放节奏由 `MusicClock.c` 的 Timer0 轮询时基调度：每次事件到期先发声，再做
整屏刷新（刷新时间与当前音符重叠），然后推进到下一个累计时值，因此刷屏不再
拖慢整曲速度。时钟刻意不使用定时器中断（SDCC 的 ISR 不保存 DPXL，可能破坏主
循环的 MOVC/@DPX 访问）；上电会用 `Ms_Delay(10)` 校准 ticks/ms，计时器失效时
退回旧的 `Ms_Delay` 节奏。`MusicClock.c` 属于 `staff` 源组，只有链接 `staff`
的音乐工程会带上它。

重新生成 `BUZZER_MUSIC_GENERATED/src/main.c` 并本地构建：

```powershell
dart run tool/generate_firmware_main.dart --project assets/templates/music.pieproj `
  --out stc32g_sdcc/projects/BUZZER_MUSIC_GENERATED/src/main.c
pwsh .\stc32g_sdcc\build.ps1 -Project BUZZER_MUSIC_GENERATED `
  -Sdcc .\vendor\sdcc-toolchain\bin\sdcc.exe `
  -LibDir .\vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
  -StdInclude .\vendor\sdcc-toolchain\include
```

主机对拍：`stc32g_sdcc/tests/test_staff_render_host.py`（需要 gcc）会把 C 渲染器
逐帧与 Dart 模拟器 golden 帧比较，并用 SDCC 编译 `StaffRender.c` 检查 C251 兼容性。

`BUZZER_MUSIC_SONG_SMOKE` 使用已有音乐项目中保存的 MIDI 解析结果，生成并播放
“【何玉】大东北我的家乡 - 原琴.mid”。其配置保存在
`projects/BUZZER_MUSIC_SONG_SMOKE/music.json`，构建命令只需将工程名改为
`BUZZER_MUSIC_SONG_SMOKE`。

语音合成示例工程 `BUZZER_VOICE_SMOKE` 把 P33 无源蜂鸣器当扬声器用：PWM 载波
固定 129.6kHz，逐样本改占空比，播出 10 阶 LPC 格型合成的中文短句
「这是P六零，电机调试」和「这是P六十，电机调试」。参考音、参数表、试听预览、
定点校验和固件构建由一条命令串起来：

```powershell
pwsh .\stc32g_sdcc\build_voice.ps1 `
  -Python <带 numpy 的 python> `
  -Sdcc .\path\to\sdcc.exe `
  -LibDir .\path\to\mcs251-large-stack-auto `
  -StdInclude .\sdcc-c251\device\include
```

脚本依次用系统中文 TTS 生成参考音、做 LPC-10 分析并量化成 13 字节/帧的参数表、
校验定点模型（含把 `voice_synth.c` 编成原生程序与 Python 定点模型逐样本比对），
调用 `build.ps1` 出 HEX，最后再扫一遍汇编做中断预算检查（热路径不允许出现
32 位乘除运行库调用）。语料在 `projects/BUZZER_VOICE_SMOKE/voice.json`，
设计与验证细节见 `docs/design/蜂鸣器LPC语音合成示例固件.md`。

### 通过代码生成器直接构建 SDCC 音乐 HEX

`build_music.ps1` 将 MIDI 解析、音乐 `main.c` 生成和 SDCC 构建串起来，默认使用
独立工程 `BUZZER_MUSIC_GENERATED`，不会覆盖上面的固定回归样例。它既接受代码生成器
配置 JSON，也可以直接接受 MIDI；MIDI 模式会自动选择第一条可播放轨道：

```powershell
$godot = 'C:\path\to\godot.exe'
$sdcc = 'C:\path\to\sdcc.exe'
$lib = 'C:\path\to\mcs251-large-stack-auto'

pwsh .\stc32g_sdcc\build_music.ps1 `
  -Midi .\song.mid `
  -Godot $godot `
  -Sdcc $sdcc `
  -LibDir $lib `
  -StdInclude .\sdcc-c251\device\include
```

输出 HEX 位于 `stc32g_sdcc/build/BUZZER_MUSIC_GENERATED/BUZZER_MUSIC_GENERATED.hex`。
如果已经通过 GUI 或 `music-config` 保存了 JSON，也可以把 `-Midi` 换成
`-Config .\music.json`。

```powershell
pwsh .\stc32g_sdcc\tests\run_qemu_smoke.ps1 `
  -Qemu C:\path\to\qemu-system-mcs251.exe
```

该 QEMU 模型是 STC32G144K246，不是 STC32G12K128；因此 QEMU 结果只作为
MCS-251 启动、UART 和基础寄存器语义的回归，NRF24L01、扩展板和精确引脚复用仍
需要桩测试或真机验证。SPI 驱动的原有 `SPI_ReadWriteByte()` API 已改为有限等待，
未接外设时返回 `0xFF`，正式工程不会因为 NRF 链路缺失永久卡死。

## USB_CDC_BRIDGE：第二块主控板做 USB-CDC 调试桥

`projects/USB_CDC_BRIDGE` 是一块固定的桥固件：第二块 STC32G12K128 烧录后，
USB（P3.0/P3.1）枚举为 CDC 虚拟串口，UART2（P1.0/P1.1）与机器人主控板
UART2 交叉相连。机器人侧的调试字节流原样转发到电脑 COM 口，电脑下发的字节
原样转发回机器人。

```powershell
pwsh .\stc32g_sdcc\build.ps1 -Project USB_CDC_BRIDGE `
  -Sdcc .\vendor\sdcc-toolchain\bin\sdcc.exe `
  -LibDir .\vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
  -StdInclude .\vendor\sdcc-toolchain\include
```

输出：`stc32g_sdcc/build/USB_CDC_BRIDGE/USB_CDC_BRIDGE.hex`。

### 接线

```text
机器人 P1.1 (UART2 TX)  ->  桥 P1.0 (UART2 RX)
机器人 P1.0 (UART2 RX)  <-  桥 P1.1 (UART2 TX)
机器人 GND              ---  桥 GND
```

只做单向打印时可以只接第一根 TX 线和 GND。两块板各自供电，不要通过调试线
互供 VCC；必须共地。

### 串口参数

- 板间 UART2 固定 **115200 8N1**。
- 电脑端 CDC 的“波特率/校验位”设置不会改变机器人链路；桥只把
  `GET_LINE_CODING` 当作回读值。
- Win10 1903+/Win11 免驱，设备管理器出现 COM 口即可用普通串口助手打开；
  Win10 1903 之前的系统需要安装 STC USB CDC 驱动。

### 诊断 LED 与“每次插拔都进 HID Writer”的排查

桥固件用主控板 LED 做状态指示（低电平点亮）：

| LED | 含义 |
|---|---|
| P3.5 亮 | 应用已启动（`main` 已运行） |
| P3.6 亮 | USB 已进入 `DEVSTATE_CONFIGURED`，CDC 应已枚举 |
| 两颗都不亮 | 应用未启动，芯片很可能还在 ROM ISP 监控程序 |

如果每次插拔 USB 都重新出现“待烧录的 HID Writer”，而 P3.5 不亮，按下面顺序排查：

1. **P3.2 在冷启动时必须为高电平。** 手册的 ISP 流程图明确：P3.0/P3.1 接着 USB 时，
   冷启动若发现 P3.2 为低，会进入【等待 USB 下载模式】。检查 P3.2 按键是否卡住、
   是否被外部电路拉低、是否有上拉电阻；必要时加 10 kΩ 上拉到 VCC。
2. **关闭 AiCube-ISP / STC-ISP 后再插拔。** 系统 ISP 监控程序会检测 P3.0 上的
   合法下载命令流；下载软件在后台运行时可能每次插拔都自动发命令，芯片就停在
   HID Writer。
3. **下载时勾选“下次冷启动时，P3.2/P3.3 为 0/0 时才可以下载程序”。** 这样正常
   冷启动会立即跑用户程序，只有按住 P3.2/P3.3 才进入下载。手册也建议这样设置。
4. **确认程序确实在跑。** 若 P3.5 亮但 P3.6 不亮，说明应用已启动、USB 未配置，
   问题转到 CDC 初始化（IRC48M、IE2、描述符/Ep0Stage、USB ISR 向量）。
   若 P3.5 不亮，说明应用没运行，仍应优先排查 P3.2 和 ISP 下载设置。
5. **已有 USB 程序的芯片不能用复位脚进入 USB 下载。** 手册说明：用户程序区已有
   CDC/HID 时，按复位脚不会进入 USB 下载模式；要重新烧录，请用“P3.2 拉低后
   冷启动”或用户程序里的 `@STCISP#` 软复位命令。

### 临时桥固件怎么切回机器人固件

桥固件只是普通用户程序，不会锁死板子。恢复机器人固件有三条路：

1. **按住 P3.2 冷启动**：P3.2 拉低后上电，ROM ISP 直接进入 HID Writer，
   用现有 USB-HID ISP 烧录机器人固件。
2. **CDC 发 `@STCISP#`**：桥固件在 PC→UART 方向匹配这个字符串，收到后
   执行 `IAP_CONTR = 0x60` 软复位到系统 ISP，HID Writer 出现后即可烧录。
   这是 STC 标准的“不停电下载”命令，不需要拔插。
3. **正常冷启动的 HID 窗口**：默认每次冷启动 ROM ISP 会先跑几十到几百毫秒，
   电脑可能短暂看到 HID Writer，随后桥固件接管为 CDC。这个窗口本身也是
   恢复入口，不需要刻意去掉。

下载时勾选“下次冷启动时，P3.2/P3.3 为 0/0 时才可以下载程序”只是把触发条件
改成“按住 P3.2/P3.3 才进 ISP”，**不会让板子无法烧录**；正常冷启动会直接跑
用户程序，需要烧录时按住按钮即可。如果想要最短启动时间可以勾选；想保留每次
冷启动的 HID 窗口也可以不勾。

### UART2_DEBUG_TEST：机器人侧 UART2 临时测试

`projects/UART2_DEBUG_TEST` 是给机器人主控板用的临时测试固件，只初始化系统
时钟和 UART2，**不初始化电机、NRF、拓展板**，测试时机器人不会动作。它用来
先验证机器人 UART2 → 桥 → USB CDC 的物理链路，再定正式协议。

```powershell
pwsh .\stc32g_sdcc\build.ps1 -Project UART2_DEBUG_TEST `
  -Sdcc .\vendor\sdcc-toolchain\bin\sdcc.exe `
  -LibDir .\vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
  -StdInclude .\vendor\sdcc-toolchain\include
```

输出：`stc32g_sdcc/build/UART2_DEBUG_TEST/UART2_DEBUG_TEST.hex`。

接线与桥一致：

```text
机器人 P1.1 (UART2 TX)  ->  桥 P1.0 (UART2 RX)
机器人 P1.0 (UART2 RX)  <-  桥 P1.1 (UART2 TX)
机器人 GND              ---  桥 GND
```

测试固件还开了一路**机器人侧 UART3 调试口**，用来单独观察 UART2 中断：

```text
USB-TTL RX  ->  机器人 P0.1 (UART3 TX)
USB-TTL GND ->  机器人 GND
115200 8N1
```

- P3.5 每秒翻转一次，做应用心跳（低电平点亮）；不闪说明应用没跑。
- UART3 只发送，不占用 UART2；桥的 UART3 调试口是另一个物理口，不要混接。

行为：

- 每 1 秒发送 `UART2 OK <counter>`；
- 收到 PC 经桥下发的字节后回显 `[RX] <byte>`；
- 115200 8N1；接收用 UART2 中断 + 64 字节环形缓冲，发送仍用查询。
  115200 下连续字节间隔只有约 87 us，主循环轮询会覆盖 `S2BUF`，
  所以 PC→机器人方向必须由中断及时搬走。

电脑 CDC 串口应看到：

```text
[UART2 TEST] P1.0=RX P1.1=TX 115200 8N1
UART2 OK 0
UART2 OK 1
...
```

在 COM 口连续发送 `hello`，5 个字节都应依次回显：

```text
[RX] h
[RX] e
[RX] l
[RX] l
[RX] o
```

如果只回显第一个 `h`，说明板上还是旧的“查询接收”版本，需要重新烧录中断版。
桥的 256 字节 `TxBuffer` 在 PC 未打开 COM 口时会累积并丢字节，正式协议需要
帧头/长度/CRC 让 PC 端重新同步；测试固件只负责验证物理链路。

机器人侧 UART3 调试口启动时应看到：

```text
[BOOT] UART2 test; UART3 debug P0.1 115200
[INIT] S2CON=50 IE2=01 EA=1
[DBG] u2irq=0 drop=0 head=0 tail=0 s2con=50 ie2=01 ea=1
```

在 CDC 连续发 `hello` 时，`u2irq` 应增加 5，`head`/`tail` 也应增加；
如果 `u2irq` 一直是 0，说明 UART2 中断没进，重点查 `IE2`、`EA`、向量表；
如果 `u2irq` 在涨但 CDC 没回显，查环形缓冲和回显逻辑。

测完后按桥的恢复流程烧回机器人固件即可；这个测试固件不写 Flash、不改
ISP 设置，不会影响后续烧录。

### 调试串口（UART3 P0.0/P0.1）

桥固件另外开了一路独立调试串口，用来打印启动/USB 状态：

- **UART3：P0.0 = RX，P0.1 = TX，115200 8N1，只发送。**
- USB-TTL 的 **RX 接 P0.1**，GND 共地即可；P0.0 可以不接。
- **不要用 P1.0/P1.1 做 printf**：那是桥的 UART2，已经用于接机器人；
  接调试器会和机器人链路冲突。

启动后串口会输出：

```text
[BOOT] IRCBAND=82
[USB] IRCBAND=82
[USB] wait IRC48M...
[USB] IRC48MCR=81
[USB] USBCLK=00 USBCON=90
[USB] init done IE2=80
[BOOT] ready
[LOOP] st=0 irq=0 rst=0 setup=0 intr=00/00/00 ie2=80 usbcon=90
```

判读方法：

- 连 `[BOOT]` 都没有：应用没跑或 UART3 没初始化，先回到 P3.5/ISP 排查。
- 停在 `[USB] wait IRC48M...`：IRC48M 没稳定，USB 初始化卡死。
- `[USB] init done` 后 `irq` 一直为 0：USB 中断没进来，检查 P3.0/P3.1、
  `IE2.EUSB`、`USBCON` 和 USB 线。
- `irq` 在涨但 `setup=0`：USB 中断进了，但没有 SETUP 包，重点查端点/描述符。
- `setup` 在涨、`st` 变成 4：枚举完成，CDC 应出现；若仍无 COM 口，
  再查描述符和 VID/PID。

### 实现说明

- 源码从 STC 官方 `70-CDC(Communication Device Class)协议范例` 移植，
  保留原始版权头；SDCC 侧使用 `__code`/`__xdata`、`__interrupt` 和
  3 字节 flat 指针。
- `IE2`、`P_SW2`、`IRCBAND`、`S2CON`、`AUXR` 都不是可位寻址 SFR，
  固件全部使用字节掩码，避免 SDCC 把伪 `__sbit` 写到错误位地址。
- **`IE2` 的 EUSB(bit7) 是只写位，读回永远为 0**。因此绝不能写
  `IE2 |= 0x80` / `IE2 &= ~0x80` / `IE2 |= 0x01`——这些读-修改-写会把
  EUSB 清掉，表现为 USB 中断永远不进（`irq=0`）。桥固件用
  `Ie2Shadow` 保存除 EUSB 外的位，写回时统一 `IE2 = Ie2Shadow | 0x80`。
  调试打印里的 `ie2` 看不到 EUSB，应看 `shadow` 和 `en`。
- EP0 描述符先复制到 XDATA `Ep0Stage`，再交给通用指针发送；
  `SETUP`/`LINECODING` 有编译期大小检查。
- UART2 环形缓冲有满检查；ISR 共享索引和标志均为 `volatile`。
- QEMU 的 `stc32g144k246` 模型不模拟 USB PHY/CDC，本工程必须真机验证。
