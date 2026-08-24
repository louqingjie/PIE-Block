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
会在每次链接后检查这些区域以及 SDCC 原生启动符号。

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

`BUZZER_MUSIC_SONG_SMOKE` 使用已有音乐项目中保存的 MIDI 解析结果，生成并播放
“【何玉】大东北我的家乡 - 原琴.mid”。其配置保存在
`projects/BUZZER_MUSIC_SONG_SMOKE/music.json`，构建命令只需将工程名改为
`BUZZER_MUSIC_SONG_SMOKE`。

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
