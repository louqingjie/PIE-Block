# PIE-Block TUI 复刻进度

> 计划：[`TUI复刻实现计划.md`](TUI复刻实现计划.md)。基线 `main@a9143e6`（1.8.0+14，`.pieproj` 格式 23）。
> 本文件随里程碑推进更新；每完成一项即提交推送。

## 状态

**当前：M0 收尾（待人工/硬件验证）+ M1 领域内核进行中**

## 里程碑清单

| 里程碑 | 状态 | 说明 |
| --- | --- | --- |
| M0 技术验证 | 🟡 收尾 | Rust 工具链、workspace、M0 演示壳、表单/卷帘原型、单元测试、CI 已就绪；待：真实终端键鼠/IME 验证、hidapi 真机、SDCC+HEX 对拍、卷帘体验评审 |
| M1 领域内核 + CLI | 🟡 进行中 | 已完成：Dart oracle golden 工具、13 份模型 golden、`.pieproj` 模型与 17→23 迁移（与 Dart 输出逐字节一致）、16 份校验 golden、公共机器人规则 + 调试工程完整规则；待：步兵/工程专属规则、音乐规则、代码生成、表达式、音乐/MIDI/五线谱、CLI |
| M2 工具链 + HID | ⬜ 未开始 | SDCC/Keil 构建、指纹/缓存、HEX/MAP、LST、hidapi 传输与烧录状态机、udev |
| M3 TUI 基座 | 🟡 部分前置 | 已有应用循环、主题、三栏布局、焦点、状态栏；待完善文件浏览器、设置、最近项目、自动保存与 PTY 测试框架 |
| M4 向导表单 | ⬜ 未开始 | 四类工程全部页面与问题跳转 |
| M5 检查/代码/汇编/表达式 | ⬜ 未开始 | |
| M6 音乐编辑器 + 音频 | ⬜ 未开始 | 卷帘原型已在 M0 演示壳中 |
| M7 烧录页与部署 UI | ⬜ 未开始 | |
| M8 跨平台发布 | 🟡 部分前置 | 已有 `tui.yml` CI（Windows/Linux）；待打包、安装器、发布流水线 |

## M0 已完成

- Rust 1.100.0（stable，x86_64-pc-windows-msvc）安装并验证 MSVC 链接。
- `tui/` Cargo workspace：`pieblock-core` / `pieblock-ui` / `pieblock-toolchain` / `pieblock-hid` / `pieblock-tui` / `pieblock-cli`。
- M0 演示壳：三栏布局、中文/宽字符、主题切换、焦点/Tab、鼠标捕获、帮助浮层、状态栏。
- 表单原型：数字/下拉/开关/滑块/中文文本输入、范围校验、保存状态模拟。
- 钢琴卷帘原型：16 行可视网格、音符绘制、光标、播放头、缩放、增删音符、鼠标定位。
- CLI 骨架：`describe` 输出契约 JSON；`validate`/`codegen` 明确标注 M1 未移植。
- 测试：核心/UI/HID/CLI 共 20+ 单元测试；`cargo fmt`、`clippy -D warnings`、`cargo test` 全绿。
- CI：`.github/workflows/tui.yml`（Windows + Linux，fmt/clippy/test/release build）。

## M0 剩余验证项（需要人工/硬件）

1. Windows Terminal + conhost 下的中文输入法、宽字符对齐、鼠标点击/滚轮。
2. GNOME Terminal / Konsole 下的同项验证（Linux 环境）。
3. 用 hidapi 枚举 VID 34BF / PID 1001 并读取一帧 `info`（需主控板）。
4. 用内置 SDCC 构建模板工程，HEX SHA-256 与 Flutter 版产物对拍。
5. 卷帘与表单在 80×24 / 120×36 的体验评审，确定 M4/M6 的键位与布局。
6. 确认 TUI 视觉风格（深色/浅色/边框/信息密度）方向。

## 下一步（M1 继续）

1. 补全校验器：步兵/工程专属规则（约 1,500 行 Dart）与音乐规则（依赖 `music.dart` / `staff_notation.dart` 移植），把校验 golden 从 remote 子集扩展到完整列表。
2. 移植表达式解析/求值/C 生成（`expression.dart`）与音乐裁决/MIDI（`music.dart`、`midi_codec.dart`）。
3. 移植代码生成器（`code_generator.dart`），以 350 份生成 C 与 6 个 HEX 哈希对拍。
4. 接 CLI 的 `validate`/`codegen`，保持现有 JSON/退出码契约。

## M1 已完成

- 开发期 Dart golden 生成器：`tui/parity/tools/bin/export_model_goldens.dart`（读取 9 份 fixture + 4 份模板，输出迁移后的 `ProjectDocument.toJson()`）。
- 13 份模型 golden：`tui/parity/golden/model/*.json`；Rust 侧对每份输入读取→迁移→写出，**逐字节**等于 Dart 生成的 wrapper（`tests/model_golden.rs`）。
- `pieblock-core::model`：4 种 config、全部枚举、`Remote/Chassis/Pwm/Axis/Debug/Music/ActionMapping/ActionTable/Mode` 模型，以及 17→23 迁移（方向折负、`wrap`/灵敏度/引脚备注缺省、`name` 忽略等）。
- `pieblock-core::document`：格式版本门禁（17–23，中文错误文案逐字一致）、向导进度、`to_pretty_string`（2 空格 + 末尾换行）、golden wrapper。
- `pieblock-core::ids`：Dart 形态的 UTC ISO8601 与 `microsecondsSinceEpoch` 风格 id。
- `pieblock-core::json`：Dart 宽容语义的数值截断、字符串/布尔/数组读取、`string_enum!` 宏、`ParamNum`（整数/小数参数）。
- `pieblock-core::validation`：公共机器人规则（遥控器/底盘/四轮共用 IO/冲刺与灵敏度警告）、调试工程完整规则（10 路固定引脚、驱动类型、值域、摩擦轮提醒）；导出 16 份校验 golden，调试工程完整列表逐条一致，工程 remote 子集完全一致、步兵 remote 子集为 Dart 输出前缀（专属规则待移植）。
- `pieblock-core::ids`：补上 Dart `toIso8601String` 的规则——微秒为 0 时 3 位小数，否则 6 位。

## M0 演示壳命令

```powershell
cd tui
.\run.ps1                  # 自动定位 cargo；Windows 建议用 Windows Terminal
.\run.ps1 -NoMouse
```
