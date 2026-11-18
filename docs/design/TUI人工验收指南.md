# PIE-Block TUI 人工验收指南

本指南用于发布前的人工/硬件验收；自动化门禁结果为 149 个测试全部通过、Windows 发布包
已重建并校验无 Dart/Flutter 文件。验收结论请按 `docs/design/TUI验收清单.md` 勾选并回填。

## 0. 环境诊断

在发布包目录或仓库 `tui` 下运行：

```powershell
tui.exe --diagnostics            # Windows
./pieblock-tui --diagnostics     # Linux
```

应输出平台、数据目录、运行时资源路径、SDCC/stc32g_sdcc 是否找到、模板目录、HID 设备数、
Linux udev 状态与 Keil 环境变量。将该输出附在验收记录中。

## 1. Windows 终端（逐项）

分别在 **Windows Terminal** 与 **conhost（传统控制台）** 执行：

1. `pieblock-tui.exe` 启动 → 首页显示、配色正常，无乱码。
2. 移动 `↑↓`、滚轮滚动最近项目列表；`N` 新建 → 类型选择 → 路径输入（含中文路径）→ Enter。
3. 向导：`↑↓` 选字段、Enter 编辑、`PgUp/PgDn` 翻页、Esc 保存返回；输入中文备注字段（IME）。
4. 概览：`C` 代码预览滚动、`G` 汇编术语浮层、`B` 构建（SDCC）→ 构建成功/缓存复用日志。
5. `F1`/`?` 帮助浮层显示与关闭；`S` 设置切换主题（深/浅）。
6. `Q` 退出 → 终端恢复正常光标/鼠标/滚动，标题栏无残留。
7. 若终端支持鼠标：向导字段点击/滚轮滚动行为正常（不支持时应可用键盘完成全部操作）。

**记录**：终端名称/版本、窗口尺寸（80×24 与 120×36 各一次）、乱码或重叠截图。

## 2. Linux 终端

在 GNOME Terminal 或 konsole 中：

1. `./pieblock-tui --diagnostics` 输出 udev 状态；如未安装按提示安装规则并重新插拔设备。
2. 启动、中文显示、`F1` 帮助、代码预览中文注释显示正常。
3. 检查无多余动态依赖：`ldd pieblock-tui`（可接受 libc/终端库等常规依赖，不应出现 Flutter/Dart）。
4. `Q` 退出后终端恢复正常状态。

**记录**：发行版、终端、locale（`echo $LANG`）、字体、截图或录屏。

## 3. 硬件烧录（当前无硬件，记为阻塞）

需要 STC32G 主控板并进入 USB 下载模式：

1. `F` 打开烧录页 → 设备数 ≥1；udev（Linux）已安装。
2. `B` 构建得到 HEX（或把 `main.hex` 放到工程旁）→ 烧录页显示 HEX 与 SHA-256。
3. Enter 烧录 → 进度/日志（擦除/写入/校验/复位）→ 成功或失败原因可读。
4. 中途 `C` 取消；重新插拔后 `R` 重新探测。
5. 对照 Flutter 桌面端同一工程构建的 HEX/MAP（同工具链版本）与 SHA-256。

## 4. Keil C251（需本机授权环境）

1. 设置中切换编译器为 Keil 并填写 Keil 安装目录（或设置 `PIEBLOCK_KEIL`）。
2. 概览 `B` 构建 → 日志应显示 `UV4 -r Project_Template.uvproj`、`0 Error(s)` 与 HEX 校验结果。
3. 无 Keil/目录错误时应显示「Keil 目录无效或缺少 C251」而不是崩溃。

## 5. 决策记录（2026-11）

- **发布**：先完成人工验收再打 Tag/创建 GitHub Release。
- **硬件**：当前无硬件，真实烧录验收记为阻塞项，不影响发布前的人工终端验收。
- **终端人工清单**：由项目所有者执行本指南并反馈结果。

验收通过后，请告知「人工验收通过」，我再执行发布步骤（打 `v0.1.0` Tag、创建 Release、
上传 Windows/Linux 包与 SHA-256）。
