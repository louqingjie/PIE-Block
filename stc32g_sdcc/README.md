# STC32G12K128 SDCC 工程

此目录是六个正式 STC32G12K128 Keil 工程的 SDCC MCS-251 迁移副本。原始
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

```powershell
pwsh .\stc32g_sdcc\tests\run_qemu_smoke.ps1 `
  -Qemu C:\path\to\qemu-system-mcs251.exe
```

该 QEMU 模型是 STC32G144K246，不是 STC32G12K128；因此 QEMU 结果只作为
MCS-251 启动、UART 和基础寄存器语义的回归，NRF24L01、扩展板和精确引脚复用仍
需要桩测试或真机验证。SPI 驱动的原有 `SPI_ReadWriteByte()` API 已改为有限等待，
未接外设时返回 `0xFF`，正式工程不会因为 NRF 链路缺失永久卡死。
