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
