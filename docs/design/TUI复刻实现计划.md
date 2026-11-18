# PIE-Block TUI 复刻实现计划

> 基线：`main@a9143e6`（2026-11-18；`pubspec.yaml` 1.8.0+14；`.pieproj` 格式 **23**，可读 17–23）。
> 已确认（2026-11-18）：MCP 本地服务不做，plan 不包含 MCP，架构保留 `Host` 抽象；
> **实现语言确定为 Rust**；**TUI 采用自身鲜明的终端设计风格，不追求与 Flutter 视觉一致**；
> **1.0 只覆盖 Windows 与 Linux**（macOS 暂不纳入，保留可移植性，后续可单独立项）。
> 目标：用 Rust 终端 UI 复刻桌面端**全部功能与 UI 信息内容**（页面、字段、状态、文案、操作、数据），
> 以 TUI 原生交互与视觉呈现；键盘全功能可用，鼠标作为增强。

## 0. 一页结论

| 项 | 结论 |
| --- | --- |
| 实现语言 | **Rust**（edition 2024，stable；发布产物不含 Dart/Flutter 运行时） |
| TUI 框架 | **ratatui 0.30.x** + **crossterm 0.29**（自建事件源抽象层；Windows 如 bracketed paste 不满足可切 **termina 0.4** 后端） |
| 交互组件 | **tui-textarea-2 0.14**（代码区/多行文本）、自研表单引擎、自研钢琴卷帘/动作表控件、**arboard 3.7**（剪贴板）、**syntect 或自研词法高亮** |
| 系统能力 | **hidapi 2.6**（Windows 纯 `windows-sys`、Linux 静态 hidraw）、**rodio 0.23**（试听，可选）、**sha2**、**clap**（CLI）、**serde/serde_json**、**unicode-width/unicode-segmentation** |
| 交付形态 | 单仓库 `tui/` Cargo workspace；`pieblock-tui`、`pieblock-cli` 两个二进制；Windows MSI/zip、Linux tar.gz/deb |
| 功能范围 | 四类工程（步兵/工程/调试/音乐）、全部向导字段、校验、C/汇编预览、SDCC/Keil 编译、HEX 校验、USB-HID 烧录、音乐卷帘/MIDI/试听、CLI、设置/最近项目/自动保存、主题与全部中文文案；**不含** Web/Android/MCP/云端编译/串口/蓝牙/3D 仿真 |
| “全部 UI 内容” | 信息架构、字段、文案、状态、操作、数据 100% 对等；视觉与交互采用 TUI 原生设计（见 §1.2/§5.0），不照搬 Flutter 的视觉与动画 |
| 代码规模 | Flutter 版需复刻的业务代码约 2.6 万行（应用层 1.53 万 + 核心/工具链/HID 库 1.18 万；核心包另有约 0.73 万行测试与 0.24 万行工具可作基准）；预计 Rust 3.5–4.5 万行（含测试） |
| 工期 | 2 名开发 + 0.5 测试/硬件约 **8–9 个月到 1.0**；单人约 **12–15 个月**（见 §8） |
| 首要风险 | 跨语言逐字节/逐文案一致、钢琴卷帘与复杂表单的终端交互、Windows 粘贴/IME、HID 真机与工具链打包 |
| 第一步 | 2–3 周 **M0 技术验证**（输入/IME、hidapi 真机烧录、SDCC 与 HEX 对拍、钢琴卷帘原型），通过后再进入 M1 |

## 1. 范围与“完整复刻”的定义

### 1.1 必须对等（P0，缺一不可）

| 模块 | 对等内容 |
| --- | --- |
| 项目生命周期 | 新建（四类工程 + 模板工程开关 + 劝阻提示）、打开、导入、最近项目（≤8）、文件名即项目名、格式 17–23 读取与自动升版写回、500ms 防抖自动保存、原子写入、保存状态徽标、退出前保存 |
| 四类工程向导 | 步兵 6 步、工程 7 步、调试 4 步、音乐 4 步；全部字段、单位、范围、默认值、空态、提示条、警告条；步骤解锁与“有错误不能前进”的阻断；步骤进度持久化 |
| 静态校验 | 通用机器人/步兵/工程/调试/音乐全部规则；错误/警告两级；字段路径定位、点击跳转并高亮、问题摘要面板、“本页 N 项错误、M 项提醒” |
| C 代码页 | 只读 C 预览、行号、语法高亮、搜索/上一个/下一个匹配、复制全部、另存为、C↔汇编切换、构建阶段/进度/骨架占位、失败重试、导出 `main.c` |
| 汇编列表页 | 按需用内置 SDCC 完整构建、链接后 `main.rst` 渲染（前 40 列弱化 + as251 着色 + C 锚点）、token 说明卡（词表全量）、复制/导出 `main.rst`、重新编译 |
| 表达式 | 工程动作行的受限表达式编辑、解析诊断、变量规则（局部/全局/先定义后使用）、编译检查（SDCC 门禁）、试算对话框（模式选择、LX/LY/RX/RY、按键、结果与变量） |
| 编译与产物 | 内置 SDCC C251（首次部署、逐文件哈希校验、重试提示）、可选本地 Keil C251（发现、目录校验、许可证写入、全量重建、受限版判定）、构建缓存、HEX 布局与校验和、导出 HEX、构建日志与取消 |
| 烧录 | STC32G ROM USB-HID ISP：VID 34BF/PID 1001、info→unlock→erase→128B 分块写→reset、90s 硬超时、同址重发 3 次、info 探活提示、单设备约束、进度/日志、取消；Linux hidraw + udev 规则安装（pkexec 与脚本两种路径） |
| 音乐编辑器 | 钢琴卷帘、选择/框选/多选拖动/改时长/画笔/删除/平移、吸附、缩放、滚动、撤销重做、Ctrl+A/C/V、Delete、重叠裁决（高低/最近/打断）、灰显、播放/暂停/停止/循环、视窗跟随、速度/拍号事件编辑、MIDI 导入（轨道选择）/导出、调号、P33 蜂鸣器试听 |
| 调试工程 | 10 路固定引脚的测试序列、启停、拖动排序、复制、驱动类型/值/时长、摩擦轮测试项、提示音试听（按已启用项数） |
| 首页与设置 | 品牌首页、新建/打开、最近项目、主题（浅/深/跟随系统）、编译器偏好、Keil 路径、向导提示抑制开关、错误/消息条、CLI PATH 维护（Windows 发行版） |
| CLI | `pieblock-cli describe/validate/codegen`、stdout/stderr 分工、JSON 契约、退出码 0–5、`--out`、UTF-8 中文输出、与 GUI 完全一致的校验与生成结果 |
| 文案 | 全部界面标题/副标题/分区/字段标签/单位/按钮/对话框/空态/错误/警告/提示/日志中文文案，语义与措辞与 Flutter 版一致 |

### 1.2 视觉与交互策略：TUI 原生，不逐项对齐 Flutter

**已确认**：不要求 TUI 与 Flutter 的视觉效果统一。TUI 允许并鼓励形成自己的设计语言；验收只要求“功能、信息、文案、状态、数据”对等，
视觉与交互按终端习惯重新设计。

TUI 原生设计原则（详细规范见 §5.0）：

1. 信息密度与键盘效率优先；鼠标为增强，不是前提。
2. 不复制 M3 视觉：不使用像素图片、转场动画、连续曲率、阴影、渐变。
3. 页面/字段/状态/文案一一可达，但布局、控件、配色、焦点模型由 TUI 自主设计。
4. 允许并鼓励 TUI 特有交互：命令面板、多窗格、快速跳转、状态栏、行内编辑、文本导出。
5. 品牌元素可选保留（PIE-Block 文本标识、青蓝/珊瑚强调色），不作为验收项。

下表只是“Flutter 提供的能力如何在 TUI 中实现”的候选做法，不是视觉复刻承诺：

| 能力 | TUI 候选实现 |
| --- | --- |
| 品牌/图片 | 文本词标、字符装饰；图片协议仅作可选彩蛋 |
| 动画/进度 | 静态状态 + 进度条 + 日志，不做动画 |
| 原生文件对话框 | 内置文件浏览器（路径输入/补全/最近目录） |
| 悬停信息 | 焦点 token 详情栏 + `Enter` 固定卡片 |
| 拖拽排序/调时长 | `Alt+↑/↓` 移动、`[`/`]` 调时长；鼠标拖拽增强 |
| 滑块 | 直接数字输入 + `←/→` 步进 |
| 钢琴卷帘 | 字符网格 + 工具模式 + 键位编辑/框选 |
| 平台专属 UI（Web/Android） | 不复刻 |

### 1.3 明确不做

- Flutter/Dart 作为运行时或依赖进入 TUI 发布产物；TUI 不调用 `pieblock-cli` 旧二进制、不依赖 Flutter 安装。
- MCP 本地服务（已下架）；`keil_server/` 云端编译；Web 版与 Android 版 UI；串口/蓝牙烧录；3D 仿真。
- **macOS：1.0 不纳入**（不构建、不测试、不发包；代码保持可移植，后续可单独立项）。
- 对 `.pieproj` 新格式的“扩展升级”：TUI 与 Flutter 版共用格式 23，不单方面升版。

### 1.4 验收原则

1. **功能对等**：§6 对等矩阵中 P0 项全部有 TUI 入口且行为一致。
2. **信息对等**：所有字段、单位、范围提示、错误/警告、帮助文案在 TUI 可见；`parity/manifest.yaml` 逐项登记。
3. **操作对等**：所有 Flutter 操作都有键盘等价路径；常用操作提供鼠标路径。
4. **数据对等**：读入 fixture 17–23 全部通过；保存结果语义等价（目标为逐字节等价）；生成的 `main.c`、校验 JSON、CLI 输出与 Flutter 实现逐字节/逐字段一致。
5. **TUI 风格一致性**：以 §5.0 设计规范为准，不要求与 Flutter 视觉一致；不依赖颜色传达关键信息，80×24 可用，键盘可完成全部 P0 操作。

## 2. 基线盘点（复刻对象）

### 2.1 仓库与版本

- 应用版本 1.8.0+14，CI 固定 Flutter 3.47.1；`lib/` 为 Flutter 应用（15,270 行 Dart），业务逻辑集中在 5 个包。
- 项目文件格式 23（`ProjectDocument.formatVersion`），兼容 17–23；`README.md` 仍写“格式 22”，以代码与格式文档为准。
- 当前发布平台：Windows（安装包/单文件便携版/zip）、Linux x64（tar.gz）、Web（只读演示）、Android（不发布正式包）；**macOS 无构建目录**。
- TUI 1.0 目标平台：**Windows 10/11 x64 + Linux x64（glibc）**；macOS 暂不纳入。

### 2.2 Flutter 分层

```text
lib/main.dart / lib/src/{home_screen,wizard_screen,controller}.dart   应用壳、导航、Riverpod 状态、自动保存
lib/src/wizard/**           10 个向导页面组件、表单控件、问题面板、底部操作坞、步骤栏
lib/src/{music_editor,asm_hover,asm_glossary}.dart   钢琴卷帘、汇编 token 悬停
lib/src/{deploy,asm_preview,expression_check}_controller_*.dart  编译/烧录/汇编/表达式检查状态机
lib/src/platform/**         设置、文档 IO、文件导出、路径、Keil 发现、udev、CLI PATH
lib/src/design/**           M3E 主题、卡片、对话框、波浪进度、Logo
packages/pieblock_core      模型/JSON/迁移/校验/代码生成/表达式/音乐/MIDI/五线谱/CLI（9,393 行纯 Dart）
packages/pieblock_toolchain SDCC/Keil 构建、HEX/MAP 校验、制品与对象缓存
packages/pieblock_hid       HID 协议 + Windows/Linux 原生传输（C/C++ FFI）
packages/pieblock_sdcc_native  Android 多进程编译桥（TUI 不需要）
```

### 2.3 功能与代码量化

| 维度 | 量化 |
| --- | --- |
| 工程类型 | 4：infantry / engineer / debug / music |
| 向导步骤 | 21：步兵 6、工程 7、调试 4、音乐 4；11 个页面组件（检查/代码/烧录共用；音乐编辑器单列） |
| 对话框 | 12 个（新建、模板劝阻、引脚占用、摩擦轮占用、任务取消、MIDI 轨道、速度事件、拍号事件、烧录安全确认、udev 安装、Keil 许可证、表达式试算） |
| 表单 | 约 150+ 个固定字段/开关，另有随配置增长的动态字段：动作行（输入/输出/控制方式/参数/变量/表达式）、动作表（2–8 档 × 引脚）、云台执行器列表、调试测试项 |
| 校验 | 6 大规则族、约 121 条直接规则 + 约 90 条范围/枚举辅助、约 208 条去重中文文案、8 个 stepId |
| 生成代码 | 4 条 emit 路径、单一 `main.c`（典型 200–400 行）、16 个表达式运行时 helper、6 个 HEX SHA-256 黄金基线、约 350 份生成 C 缓存样本 |
| 音乐 | PPQ 默认 480、128 音高 × 网格、单音裁决 3 策略 + 打断、MIDI format 0/1 读写、128×64 OLED 五线谱（66 帧逐字节 golden） |
| 内置工具链 | Windows SDCC C251 产物约 23 MB、155 文件、逐文件 SHA-256（Linux 由脚本现场构建同布局）；固件源码 `stc32g_sdcc` + `stc32g/Libraries` 构建资源 |
| 测试 | 核心包 261 用例、根测试约 346 用例、HID 13、工具链 29；含 9 份格式 17–22 fixture |
| 平台差异 | Windows/Linux 有本地编译与烧录；Web 只读演示；Android 不发布正式包；macOS 无实现 |

### 2.4 现有测试可作为复刻验收基准（直接复用）

- `.pieproj` 9 份兼容 fixture + 迁移条款（17→18 动作表、18→19 方向正负、19→20 引脚备注、20→21 移除 name、21→22 wrap、22→23 灵敏度）。
- 代码生成：核心包单元测试（逐特性/逐字节）、`tool/verify_runtime.dart` 的 14 步兵 + 13 工程变体与 19 个运行时场景、约 350 份生成 C 样本。
- 固件：6 个 HEX SHA-256 基线（Windows 与 Android SDCC 字节一致）、五线谱 66 帧 SSD1306 golden。
- CLI：9 个契约用例（stdout/stderr/退出码/字段）。
- UI：106 个 widget 测试可转写为 TUI 场景测试（可见性、文案、状态、断点、快捷键、双主题）。

## 3. 技术选型

### 3.1 候选方案对比（2026-11 现状）

| 维度 | **Rust + ratatui**（推荐） | Go + Bubble Tea v2 | Python + Textual |
| --- | --- | --- | --- |
| 开发效率 | 中（表单/网格/高亮需自研） | 高（bubbles 组件全、生态成熟） | 最高（组件与测试最省事） |
| 性能/重绘 | 最高（无 GC，钢琴卷帘/大段 C 列表） | 高 | 低（大列表/连续重绘易卡） |
| 单二进制 | ✅ MSI/zip/tar.gz（cargo-dist） | ✅ CGO=0 全静态；MSI 需另配 | ❌ 需 PyInstaller/Nuitka，体积大、杀软误报 |
| Windows 输入 | 键位最准；**crossterm 0.29 不解析 bracketed paste**，需 arboard/termina 兜底 | 最好（VT 输入 + 粘贴 + Kitty 协议） | 中 |
| HID 烧录 | ✅ hidapi：Windows 纯 `windows-sys`、Linux 静态 hidraw | 需 cgo（破坏静态交叉编译优势） | 需 hidapi 绑定 |
| 中文/宽字符 | ✅ ratatui-core 直接用 unicode-width/segmentation，双宽不变量明确 | ✅ uniseg/runewidth 覆盖好 | 中（rich 宽度问题多） |
| 长期维护 | 强（crates 拆分中，需锁版本） | 强 | 中 |
| 与本项目模型的契合度 | 高：sealed 类/16 个枚举/大量 `switch` → Rust enum + 穷尽匹配 | 中：缺 sum type，11 个页面分支易漏 | 中 |

### 3.2 推荐：Rust + ratatui，理由

1. **模型移植最不易漏分支**：核心包有 4 种 sealed `*Config`、16 个枚举、校验/生成两条大 `switch`；Rust 的 enum + 穷尽匹配能在编译期把“漏处理一种工程类型”变成编译错误。
2. **单二进制分发最适合学生环境**：MSI + zip + tar.gz，无 Python/Java 运行时，无杀软误报；`cargo-dist` 直接产出 MSI。
3. **HID 是硬功能**：`hidapi` 在 Windows/Linux 均无需额外 C 库（Windows 用 `windows-sys`、Linux `linux-static-hidraw`），可进程内完成烧录；这是 Go 路线必须 cgo 的地方（macOS 能力暂不纳入 1.0）。
4. **CJK 可控**：`ratatui-core` 直接吃 `unicode-width`/`unicode-segmentation`/`unicode-truncate`，中文表单和钢琴卷帘的列宽可验证；避免“按字符数当列宽”的经典 panic。
5. **性能**：钢琴卷帘逐帧渲染、几百行 C/汇编高亮、烧录日志滚动不需要 GC 抖动。
6. **一套 workspace 同时产出 TUI 与 CLI**：共享 `pieblock-core`，CLI 只依赖核心包，体积极小，天然与 GUI 一致。
7. **打包与签名链成熟**：cargo-dist（MSI/zip/tar.gz）、cargo-deb、GitHub Actions 双平台原生构建；不依赖交叉编译。

**主要代价**：Rust 开发速度低于 Go/Python；`tui-textarea` 停滞需换 `tui-textarea-2`；crossterm 0.29 的 Windows 粘贴缺陷需绕行；表单/网格/高亮没有现成组件，是本项目最大工时来源。

### 3.3 依赖清单（版本在 M0 锁定；以下为调研时最新稳定版）

| 用途 | 库 | 备注 |
| --- | --- | --- |
| TUI 渲染 | `ratatui` 0.30.2（`ratatui-core` 0.1.x、`ratatui-widgets` 0.3.x） | 锁定 minor；0.30 已拆 crate |
| 终端后端 | `crossterm` 0.29.0；`termina` 0.4（备选） | 自建 `event` 薄层，后端可替换 |
| 多行文本/代码 | `tui-textarea-2` 0.14 | 只读展示 + 搜索；`tui-textarea` 0.7 已停滞 |
| 单行输入/列表/树 | `tui-input` 0.15、`tui-tree-widget` 0.24（按需） | 自研表单控件为主 |
| 序列化 | `serde`、`serde_json` | `.pieproj`、CLI JSON、golden |
| 时间 | `jiff` 或 `time` | UTC ISO8601，与 Dart `toIso8601String` 对齐 |
| CLI | `clap` 4.x | 与现有 CLI 契约一致 |
| HID | `hidapi` 2.6.7 | 特性：Windows `windows-native`、Linux `linux-static-hidraw` |
| 哈希/HEX | `sha2`、自研 Intel HEX 解析 | 与现有校验/缓存键一致 |
| 音频 | `rodio` 0.23（`default-features=false, playback`） | Linux 构建需 `libasound2-dev`；失败降级 BEL/静音 |
| 剪贴板 | `arboard` 3.7（`default-features=false`） | 加 OSC52 兜底（SSH） |
| 高亮 | `syntect` 5.2 或自研词法 | 汇编 as251 词表必须自研（对齐现有 token 规则） |
| 字符宽度 | `unicode-width` 0.2、`unicode-segmentation` 1.12 | CJK/代理对 |
| 错误/日志 | `thiserror`、`tracing`、`tracing-appender` | 本地日志，不联网 |
| 测试 | `insta`、`proptest`、`assert_cmd`、`portable-pty` | 快照/属性/CLI/PTY 端到端 |
| 打包 | `cargo-dist` 0.34、`cargo-deb`、`cargo-wix`（备选） | MSI、zip、tar.gz、deb |

### 3.4 “不使用 Flutter/Dart”的边界

- **发布产物零 Dart**：TUI 安装包不包含 Dart VM、Flutter 引擎、`pieblock-cli` 旧二进制；运行时完全静态/动态链接，只依赖系统库（Windows 系统 DLL、Linux glibc/ALSA）。
- **开发/CI 期允许 Dart 作为“黄金基准生成器”**：仓库里已有完整的 Dart 实现与测试，用它生成并提交 `parity/golden/**`（JSON/C/HEX/MIDI 期望值）；Rust 测试只读这些快照，构建不要求安装 Dart。若要求连开发期也不出现 Dart，则改为一次性人工生成快照并冻结，后续升级需人工维护（需用户决策，见 §12）。
- 与 Flutter 版**共存**：`tui/` 作为同一仓库子目录，共享 `assets/templates/`、`packages/pieblock_core` 的 fixture、`stc32g_sdcc` 与 `vendor/sdcc-toolchain` 构建产物；Flutter 构建链保持不变。

### 3.5 语言决策与备选记录

- **已确认（2026-11-18）：Rust**。本计划按 Rust 执行，M0 后不再切换语言。
- Go + Bubble Tea v2 / Python + Textual 仅作历史备选记录（见 §3.1 对比），不进入当前路线；若后续人力出现重大变化，按 §11 R12 单独立项重评。

## 4. 总体架构

### 4.1 Cargo workspace（建议目录）

```text
tui/
├── Cargo.toml                     # workspace、lint、profile
├── rust-toolchain.toml            # 锁定 stable 版本
├── assets/                        # 从仓库 assets/ 复制（构建脚本同步）
├── crates/
│   ├── pieblock-core/             # 模型/JSON/迁移/校验/代码生成/表达式/音乐/MIDI/五线谱/CLI 命令实现
│   ├── pieblock-toolchain/        # SDCC/Keil 构建、运行时部署、指纹、HEX/MAP、制品/对象缓存、LST
│   ├── pieblock-hid/              # HID 帧协议、Flasher、hidapi 传输、udev 安装
│   ├── pieblock-ui/               # 主题、布局、表单控件、钢琴卷帘、代码视图、对话框、键位/焦点
│   ├── pieblock-tui/              # 主程序：应用循环、页面、状态机、worker 调度
│   └── pieblock-cli/              # describe/validate/codegen
├── xtask/                         # 打包资源、golden 对拍、parity 清单校验
├── parity/
│   ├── manifest.yaml              # 屏幕/字段/对话框/操作对等清单
│   └── golden/                    # 提交到 git 的期望值快照
└── tests/                         # PTY 端到端、跨 crate 集成
```

### 4.2 模块职责与边界

| crate | 职责 | 明确不做 |
| --- | --- | --- |
| `pieblock-core` | 纯逻辑，无 I/O、无终端；`ProjectDocument`/4 种 Config/枚举/serde/迁移；Validator；CodeGenerator；Expression；Music/MIDI/Staff；模板解析；CLI 的 `run()` | 不弹 UI、不读写文件、不调编译器 |
| `pieblock-toolchain` | 定位发布资源、部署内置 SDCC（哈希校验/`.ready`/重试）、构建指纹、SDCC/Keil 调用、进度事件、HEX/MAP 校验、制品与对象缓存、`main.rst` 读取、取消（进程树） | 不拥有 UI 状态 |
| `pieblock-hid` | HID 帧编解码、HEX→块映射、烧录状态机、设备枚举、错误分类、udev 检查/安装 | 不直接渲染 |
| `pieblock-ui` | 可复用 TUI 组件与布局；主题 token；焦点/键位路由；表单字段控件；代码/汇编视图；钢琴卷帘；对话框栈 | 不依赖具体页面业务 |
| `pieblock-tui` | `AppState`、reducer/command、页面组合、自动保存、worker 事件→状态、CLI PATH 维护、退出清理 | 不复制核心逻辑 |
| `pieblock-cli` | 参数解析、退出码、stdout/stderr 契约、`--out` | 不含 TUI 依赖 |

### 4.3 关键流程

```text
打开/新建 → ProjectRepository（原子写）→ AppState.document
编辑字段 → update_config → 500ms 防抖 save → 保存状态徽标
          └→（按需）Validator → 问题列表 → 字段标红/问题面板/跳转
生成代码页 → CodeGenerator → 只读渲染；切汇编 → ToolchainBuild(SDCC) → 事件流 → main.rst 渲染
烧录页 → 选择编译器 → Fingerprint → 制品缓存命中? → BuildWorker → HEX 校验 → Flasher Worker → 进度/日志
CLI → core::run(args) → JSON/C → stdout
```

### 4.4 状态与命令模型

- `AppState`：文档、路径、步骤、最近项目、保存状态、消息、问题缓存、编译器偏好、Keil 路径、主题、编辑器状态（滚动/焦点/选择）。
- 事件：`Action`（键鼠/命令）→ `Reducer`（就地更新状态）→ 副作用 `Command`（保存、构建、烧录、音频、文件浏览）。
- 自动保存：与 Flutter 一致 500ms 防抖；串行写队列；退出/关闭项目先 `save_now()`；写入失败显示可重试消息，不阻塞编辑。
- 工作区一致性：同一进程单实例（文件锁）；`.pieproj` 由 TUI 与 Flutter 版共享，但**数据目录分离**（避免两套 settings 互相覆盖）。
- 未来 MCP 位：`Host` trait（`snapshot/apply/issues/record`）留在 `pieblock-tui`，当前不实现服务；将来加 HTTP 层即可复用补丁语义。

### 4.5 并发、取消与音频

- 构建/烧录在独立线程（`std::thread` + `mpsc` 事件流）；UI 只消费事件，主循环不阻塞。
- 取消：构建用 `Child::kill` + 进程树终止（Windows Job Object / `taskkill /T`；Linux 进程组 `killpg`）；烧录通过传输层 cancel 句柄（hidapi 关闭设备 + 超时回退）；90s 看门狗。
- 音频：独立播放线程（`rodio`），UI 只发“播放/停止/音高”命令；音频不可用时降级 BEL；试听为可选功能，不阻塞核心流程。
- 设备轮询：部署页每秒一次设备枚举（与 Flutter 一致），空闲时降频。

### 4.6 TUI 渲染与输入架构

- 交替屏幕（alternate screen）+ 原始模式；只在状态变化/定时器（播放头/进度）时重绘，目标 60fps 上限。
- 三层：`event source`（crossterm/termina，统一成 `InputEvent`）→ `router`（焦点树 + 模态对话框 + 全局键位）→ `widget`。
- 焦点：显式 `FocusTree`（页面 → 表单区块 → 字段 → 编辑器），Tab/Shift-Tab 遍历，未获得焦点的字段不接收按键；模态层（对话框/下拉）独占。
- 鼠标：点击聚焦/激活、滚轮滚动、拖拽排序/滚动条/音符；鼠标事件仅在支持终端启用（可通过 `--no-mouse` 关闭以便复制文本）。
- 中文输入：终端提交的文本按 UTF-8 接收；输入框按 `unicode-segmentation` 处理光标与退格；组合期间不做实时校验（多数终端不在组合期发送字节）；长文本（表达式/路径）支持外部编辑器逃生口。
- 粘贴：`Event::Paste` + `Ctrl+V` 读系统剪贴板双通道；Windows 由 `arboard`/termina 兜底；多行粘贴按字段类型决定是否接受换行。
- 剪贴板：`arboard` 失败时写 OSC52（SSH 场景）；复制 C/汇编时优先系统剪贴板，同时提供“导出到文件”。
- 尺寸：监听 Resize 重建布局；低于 80×24 显示“请放大终端”而非崩溃；关键页面在 80×24 仍可操作。

### 4.7 一致性策略（跨语言对拍）

1. **基准生成（开发/CI）**：在 Flutter 仓库用现有 Dart 实现 + 现有测试用例生成 `parity/golden/**`：`.pieproj` 规范化输出（字节）、校验问题列表（顺序+文案）、`main.c`（字节）、表达式 AST/C/求值、MIDI 解析/导出、五线谱数据、CLI JSON、HEX SHA-256。
2. **Rust 实现**：按同一份规格重写；每个模块先跑 golden 再写 UI。
3. **提交快照**：golden 入 git，Rust CI 无需 Dart；Flutter 侧变更 golden 时触发 TUI CI 红，强制同步。
4. **对拍范围**：9 份格式 fixture、四类模板、`verify_runtime` 的 27 个变体 + 120 随机工程、350 份生成 C、6 个 HEX 哈希、66 帧五线谱、所有 UI 文案清单。
5. **禁止静默降级**：遇到无法对拍的行为差异必须显式登记到 `parity/known-deviations.md` 并由维护者签字。

### 4.8 文件、路径与跨平台行为（1.0：Windows + Linux）

| 行为 | Windows | Linux |
| --- | --- | --- |
| 应用数据目录 | `%APPDATA%\com.wpie\PIE-Block-TUI\`（独立于 Flutter 版） | `$XDG_DATA_HOME/com.wpie/PIE-Block-TUI/` |
| 设置 | `settings.json`（字段与 Flutter 版兼容子集：theme/recent/compiler/keil_path/suppress_*） | 同左 |
| 缓存 | 制品、对象缓存、日志子目录；与 Flutter 版分开，避免指纹混用 | 同左 |
| 内置 SDCC | 复用 `vendor/sdcc-toolchain`（Windows 构建产物），按 manifest 哈希部署 | 复用 Linux 构建产物 |
| Keil | 支持（发现/许可/全量构建） | 理论支持但不承诺（无官方 Keil Linux） |
| 烧录 | hidapi + Win32 HID | hidapi + hidraw + udev |
| CLI | 同仓库产物；PATH 维护可选 | 同左，不改 shell rc |

> macOS 不在 1.0 范围；`pieblock-core` 保持无平台依赖，`hidapi`/音频/路径层按 trait 隔离，便于后续启用。

## 5. TUI 设计与功能映射

### 5.0 TUI 设计语言（自身规范）

- **布局**：全屏 alternate screen；顶部标题/面包屑行、主工作区、底部状态栏（保存状态、问题计数、当前键位提示）；宽屏使用多窗格（步骤栏/主内容/详情栏），窄屏单栏。
- **视觉**：单线/双线边框 + 反色选中 + 语义颜色；无圆角、无阴影、无动画；焦点用反色/边框加粗；错误用 `✖` + 文字，不只靠红色。
- **信息密度**：一屏尽量展示完整分组；长表单用 Tab/折叠分区；表格支持横向滚动与固定列。
- **键盘优先**：所有操作都能用键盘完成；`F1` 帮助、`Ctrl+P` 命令面板、`?` 显示当前页快捷键；键位全局一致，冲突有提示。
- **鼠标增强**：点击/滚轮/拖拽（排序、滚动条、音符），`--no-mouse` 可关闭。
- **可复制性**：代码/汇编/日志/问题列表支持选中或导出文本；不把关键信息画在不可复制的图形里。
- **主题**：深色/浅色/高对比三套；`NO_COLOR` 降级；品牌色仅作强调。
- **终端要求**：UTF-8、支持 ANSI 颜色与鼠标上报；推荐 Windows Terminal / GNOME Terminal / Konsole，最小 80×24。

### 5.1 屏幕映射（功能对等，非视觉复刻）

> 下表描述“信息/能力对应关系”，列出的布局是 TUI 推荐实现，不要求与 Flutter 的排布一致。

| Flutter 界面 | TUI 屏幕 | 布局 |
| --- | --- | --- |
| 首页（品牌/新建/打开/最近项目/主题） | `Home` | 居中面板 + 两列动作卡 + 最近项目表格 + 底部状态/键位提示 |
| 向导壳（步骤栏/内容区/操作坞/问题面板/保存徽标） | `Wizard(kind)` | ≥120 列：左侧 22 列步骤栏 + 主内容 + 右侧详情栏（问题/token）；<120 列：顶部步骤选择条 + 主内容 |
| 遥控器与底盘 | `Wizard/Remote` | 分区表单（Section）两栏/单栏自适应 |
| 云台与拨弹（步兵） | `Wizard/Mechanism` | 分区 + 执行器列表（可增删） |
| 控制与摩擦轮（步兵） | `Wizard/Controls` | 分区表单 + 条件字段显隐 |
| PWM 与引脚（工程） | `Wizard/Pwm` | 引脚表格（10 行 × 角色/中位/限幅/上限/备注） |
| 模式切换（工程） | `Wizard/Strategy` | 表单 + 每模式按键行 |
| 动作映射（工程） | `Wizard/Mappings` | 模式页签 + 动作卡片列表 + 动作表卡片（表格） |
| 测试序列（调试） | `Wizard/DebugTests` | 10 张测试卡 + 提示音试听区 |
| 钢琴卷帘（音乐） | `Wizard/Music` | 工具栏 + 事件栏（BPM/拍号）+ 琴键列 + 网格 + 播放头；详情栏显示选中音符 |
| 检查与摘要 | `Wizard/Review` | 问题列表（可跳转）+ 配置概览 + 表达式检查/试算入口 |
| 生成代码 | `Wizard/Code` | 工具栏（C/汇编、搜索、复制、导出、重编译）+ 代码/列表视图 + 构建进度条 |
| 烧录 | `Wizard/Deploy` | 编译器、构建产物、HID 设备、进度与日志四分区；日志面板可滚动/跟随 |
| 12 个对话框 | `Overlay`（居中/底部弹出） | 统一表单式对话框，`Tab` 切按钮，`Esc` 取消，`Enter` 确认 |
| 消息条/保存徽标/问题摘要 | 状态栏 + 右上角标志 + 右侧详情栏 | 不阻塞编辑；错误需显式确认 |

### 5.2 控件选型（TUI 原生）

> 仅说明信息如何承载；控件外观按 §5.0 设计语言实现，不要求与 Flutter 控件形似。

| Flutter 控件 | TUI 控件 | 键位 |
| --- | --- | --- |
| TextField（数字/文本/路径） | 单行输入框：值 + 单位 + 范围提示 | `Enter` 编辑/提交，`Esc` 取消，`Ctrl+E` 外部编辑器 |
| 带符号数字/两位小数 | 校验数字输入（保留负号与小数白名单） | `↑/↓` ±1，`Shift+↑/↓` ±10 |
| DropdownButtonFormField | 下拉列表（可过滤） | `Enter` 打开，`↑/↓` 选择，`Enter` 确认 |
| 分段按钮（项目类型/输出语言/工具） | 一行段选（`[ ]`/`(*)`） | `←/→` 切换 |
| SwitchListTile / Checkbox | `[x]`/`[ ]` 切换 | `Space` |
| Slider（灵敏度 10–200%） | 数字输入 + `←/→` 步进 5，右侧百分比 | `←/→`、`PageUp/PageDown` |
| 引脚选择（含占用/交换） | 下拉 + 冲突标记；确认用同一语义对话框（解除/交换/取消） | 同下拉 |
| 动作行卡片 | 列表项 + 内联字段；`Alt+↑/↓` 调整顺序，`d` 复制，`Delete` 删除 | 见 §5.6 |
| 动作表（引脚 × 档位） | 二维表格，冻结引脚列，横向滚动 | `h/l` 或 `Shift+滚轮` 横向，`Enter` 编辑单元格 |
| 问题列表/摘要面板 | 右侧详情栏或底部面板；`F6` 开关，`Enter` 跳字段 | `n/p` 上下问题 |
| 代码编辑器 | 只读代码视图（行号、高亮、选择、搜索） | `/` 搜索，`n/N` 匹配，`y`/`Ctrl+C` 复制 |
| 汇编悬停卡 | 光标下 token 详情（详情栏），`Enter` 完整卡片 | 见 §5.6 |
| SnackBar/Banner | 状态栏消息（info/warn/error）+ 可关闭的顶部条 | `F8` 查看历史消息 |
| 模态确认 | 对话框（红色标题 + 危险操作二次确认） | `Tab` 按钮，`Enter` 确认 |
| 拖拽排序 | 键位移动 + 鼠标拖拽（可选） | `Alt+↑/↓` |

### 5.3 终端尺寸与断点

- 最低可用：**80×24**（全部 P0 操作可完成）；推荐：**120×36**；宽屏：**≥160×40**。
- 断点：`<100` 紧凑（单栏、隐藏详情栏、操作提示压缩）；`100–139` 标准（步骤栏收窄/顶部步骤条）；`≥140` 宽屏（步骤栏 + 主内容 + 详情栏）。
- 对话框最大宽度 `min(80, 终端宽-4)`；长文本自动换行；表格列宽按 `unicode-width` 计算，中文列按双宽。
- 窗口过小时显示“最小 80×24”提示，保留 `Ctrl+Q` 退出，不渲染半截界面。

### 5.4 全局键位（草案，M0 用真实终端验证）

| 键 | 功能 |
| --- | --- |
| `Tab` / `Shift+Tab` | 焦点前进/后退 |
| `↑↓←→` / `PgUp/PgDn` / `Home/End` | 移动/滚动；字段内为调整或移动光标 |
| `Enter` | 编辑/确认/进入 |
| `Esc` | 取消编辑/关闭弹层（不丢弃已提交字段） |
| `Ctrl+S` | 立即保存（自动保存之外的显式保存） |
| `Ctrl+Q` | 退出（有未保存/构建中时确认） |
| `F1` | 帮助/当前页快捷键 |
| `Ctrl+P` | 命令面板（跳步骤、新建/打开、切换主题、导出、重编译等） |
| `F6` | 问题面板开关 |
| `F7` / `F8` | 检查与摘要 / 生成代码 |
| `Alt+1…7` | 跳转到向导第 N 步（有未保存阻断时同样校验） |
| `Ctrl+←/→` | 上一步/下一步 |
| `Ctrl+Z` / `Ctrl+Y` | 编辑器内撤销/重做（音乐、表达式） |
| `Ctrl+A` / `Ctrl+C` / `Ctrl+V` | 全选/复制/粘贴（编辑器与代码视图） |
| `Ctrl+F` 或 `/` | 代码/列表搜索 |
| `F5` | 重新编译（代码/烧录页） |

### 5.5 表单、焦点与校验导航

- 分区（Section）标题可折叠；Tab 顺序 = 视觉顺序；`Enter` 进入字段编辑，编辑态 `Esc` 回到浏览。
- 字段级错误：字段行尾 `✖/⚠` + 错误文本（不依赖颜色）；`F6` 问题面板中 `Enter` 跳转到对应步骤并聚焦字段，高亮闪烁 1.4s（与 Flutter 一致）。
- 步骤阻止：`下一步` 时若当前步及之前有 error，定位到第一条并展示“发现 N 项错误，请修正标红的配置”，与 Flutter 行为一致。
- 空态/加载/失败：统一 `EmptyState` 组件（文案 + 操作提示）；构建/烧录进度用单行进度条 + 阶段文本 + 日志面板。
- 危险操作（烧录、udev、Keil 许可证、退出构建）保持 Flutter 的确认语义与文案（图片改为文字清单）。
- 表单即时校验与保存解耦：输入不合法时保留草稿并提示，不阻塞其他字段；失焦/提交时按字段白名单修正（负号、两位小数、整数夹取），与 Flutter 输入框行为一致。

### 5.6 页面级键位（草案）

- **审核/检查页**：`↑/↓` 选问题，`Enter` 跳转；`c` 检查表达式，`t` 试算（工程且存在表达式行时）。
- **代码页**：`Tab` 在工具栏/代码区切换；`/` 搜索，`n/N`；`c` 复制，`e` 导出，`r` 重编；`m` 切 C/汇编；`↑/↓/PgUp/PgDn` 滚动；`Home/End` 行首尾；`g/G` 顶/底。
- **烧录页**：`c` 编译并烧录，`b` 仅编译，`f` 烧录当前固件，`x` 取消，`e` 导出 HEX，`d` 重新检测设备，`l` 切换日志跟随。
- **音乐页**：`Space` 播放/暂停，`s` 停止，`1/2/3/4` 工具（选择/画笔/删除/平移），`←/→` 移动光标，`Shift+←/→` 框选，`Ctrl+A/C/V`，`Delete`，`[`/`]` 调时长，`z/x` 缩放，`,`/`.` 吸附，`Alt+↑/↓` 改变音高（选中音符），`Ctrl+M` MIDI 导入，`Ctrl+E` 导出 MIDI，`t` 速度事件，`b` 拍号事件。
- **首页**：`n` 新建，`o` 打开，`r` 最近项目，`t` 切主题，`?` 帮助；`Tab` 在卡片/最近项目间切换。
- **汇编列表**：方向键移动光标；光标所在列决定详情（前 40 列解释地址/机器码/周期/行号；正文 token 显示中英文说明与位地址/十进制值）；`Enter` 固定卡片，`Esc` 关闭。

### 5.7 鼠标契约

- 左键单击：聚焦字段/按钮/步骤/表格单元格；双击：进入编辑/切换开关。
- 滚轮：垂直滚动；`Shift+滚轮`：水平滚动；`Alt+滚轮`：数值步进。
- 拖拽：滚动条、动作/测试项排序、音符移动/右缘调时长、框选；拖拽时禁用文本选择并显示目标位置。
- 悬停：仅用于详情栏预览（200ms 延迟），不改变焦点；`--no-mouse` 时全部功能仍可用键盘完成。
- 终端级限制：鼠标上报会阻止按住 Shift 以外的原生选择；在帮助中说明“按住 Shift 可选中文本复制”。

### 5.8 关键界面草案（宽屏 120×36）

```text
┌ PIE-Block TUI · 我的机器人（步兵项目） ───────────── 已保存 · 问题 0 ──┐
│ 步骤            │ 云台与拨弹机构                                      │
│ ✓ 1 遥控器与底盘│ 配置固定执行机构。主控板 MP03/MP74 只能连接舵机。     │
│ ▶ 2 云台与拨弹  │ ┌ 拨弹电机 ────────────────────────────────────────┐ │
│   3 控制与摩擦轮│ │ 扩展板 IO  [P60        ▾]   方向 [正向 ▾]        │ │
│   4 检查与摘要  │ └──────────────────────────────────────────────────┘ │
│   5 生成代码    │ ┌ Yaw 轴 ──────────────────────────────────────────┐ │
│   6 烧录        │ │ 驱动 [舵机 ▾]  IO [MP03 ▾]  方向 [正向 ▾]       │ │
│                 │ │ 归中偏移 [ 0]°  限幅 [ 0]°  [ 0]°   [删除]        │ │
│                 │ │ > 添加执行器                                      │ │
│                 │ └──────────────────────────────────────────────────┘ │
│                 │  Yaw 灵敏度 [100]%  ←/→ 步进 5                        │
├─────────────────┴──────────────────────────────────────────────────────┤
│ F1 帮助  F6 问题  Enter 编辑  Tab 切换  Ctrl+P 命令  Ctrl+S 保存        │
└────────────────────────────────────────────────────────────────────────┘
```

```text
┌ 生成代码 ───────────── [C] 汇编  / 搜索: LX       3/12  ⧉复制  ⇩导出 ┐
│  1  #include "main.h"                                                  │
│  2                                                                     │
│  3  void UpdateGimbal(void) {                                          │
│  4    gimbalYawDuty = ServoDuty(750 + (int)(LX * 1000.0f / 2047.0f));  │
│  5  }                                                                  │
├────────────────────────────────────────────────────────────────────────┤
│ 编译  [##########--------------------] 12/22 编译 gimbal.c             │
└────────────────────────────────────────────────────────────────────────┘
```

```text
┌ 钢琴卷帘（音乐项目） 480 PPQ · 120 BPM · 4/4 ──────────────────────────┐
│ 工具 选择 画笔 删除 平移 │ 吸附 1/16 │ 重叠 取最近音阶 │ ▶ 播放  ■ 停止 │
│  BPM 120  4/4 │ C5 ┤     ███        ██                                │
│               │ B4 ┤  ███  ███   ██                                   │
│               │ A4 ┤        ░░░░  ███     ← 灰色 = 裁决后不发声        │
│               │ G4 ┤  ████        ░░░                                │
└──────────────────── 小节 1 ───────── 小节 2 ──────────────────────────┘
```

### 5.9 主题、配色与可访问性

- 主题：浅色/深色/跟随系统（TUI 无法可靠读取系统主题，默认深色，提供显式切换并记忆；可用 `COLORFGBG` 做启发式初值）。
- 配色：TUI 自有语义色板，可选沿用品牌青蓝 `#02ACC0`/珊瑚粉 `#EF685D` 作强调；语义色（成功/警告/错误/选中）按 TUI 规范定义；支持 24-bit、256 色、16 色降级；`NO_COLOR`/`--no-color` 时仅用符号与反色。
- 不依赖颜色表达危险/错误：同时使用 `✖/⚠/✓`、反色和文本。
- 字体：终端等宽 + 支持 CJK 的字体（Windows Terminal 默认即可；推荐等距更纱黑/Maple Mono NF + 思源黑体）；避免 EAW=Ambiguous 字符画边框。
- 减少动态效果：默认关闭闪烁/滚动动画；`--reduced-motion` 强制静态；进度条只在数值变化时刷新。
- 无障碍边界：TUI 对读屏软件支持有限，文档中明确“键盘全功能、颜色非唯一信息、可导出文本”。

### 5.10 TUI 风格约定（非 Flutter 适配项）

1. 不使用像素图片/动画/渐变/阴影；品牌用文本标识与颜色表示。
2. 文件选择使用内置文件浏览器，不调用原生对话框（可选“用系统打开”作为辅助）。
3. 悬停信息以焦点详情栏/固定卡片呈现，鼠标悬停可触发但不作为唯一入口。
4. 排序/调时长提供键位（`Alt+↑/↓`、`[`/`]`）与鼠标拖拽两条路径。
5. 钢琴卷帘使用字符网格；播放头、灰显、选中用颜色 + 符号双编码。
6. 主题手动切换并记忆（终端无法可靠读取系统主题）；`COLORFGBG` 仅作初值。
7. 提供 `--no-color`、`--no-mouse`、`--reduced-motion` 与 `F1` 帮助，保证受限环境可用。

## 6. 功能对等矩阵

> P0 = 1.0 必须完成；P1 = 1.0 可降级但功能必须存在；验收方式中“golden”指 §4.7 快照对拍，“PTY”指伪终端端到端测试，“HIL”指真机在环。

| # | 模块 | 对等内容 | 优先级 | 验收方式 |
| --- | --- | --- | --- | --- |
| 1 | 项目生命周期 | 新建/打开/导入/最近项目/文件名派生名/500ms 自动保存/原子写/保存徽标/退出保存/格式 17–23 升版写回 | P0 | golden + PTY + 人工 |
| 2 | 首页与设置 | 品牌区、新建/打开、最近类型图标、主题三态、编译器/Keil 路径、提示抑制、消息条、Windows CLI PATH 维护 | P0 | 快照 + 人工 |
| 3 | 新建项目 | 四类分段、模板开关与劝阻确认、“以后不再提示”、名称/路径双向同步、路径浏览、创建失败提示 | P0 | PTY + 快照 |
| 4 | 步兵配置 | 遥控器与底盘（13 字段）、云台/拨弹（执行器增删、限幅、灵敏度）、控制与摩擦轮（按键/速度/映射/高级） | P0 | golden + PTY + 当前版 widget 测试转写 |
| 5 | 工程配置 | 遥控/底盘、PWM 10 引脚角色/频率/中位/限幅/上限/备注、模式 1–4 与切换策略、动作行全字段、动作表全字段、表达式/变量、复制/删除/排序 | P0 | golden + PTY + 快照 |
| 6 | 调试配置 | 10 路测试项顺序/启停/复制/驱动/值/时长、提示音试听与音型说明 | P0 | golden + PTY |
| 7 | 音乐配置 | 卷帘编辑全部操作、吸附/缩放/撤销、重叠裁决与灰显、速度/拍号事件、调号、MIDI 导入导出、播放控制 | P0 | golden + PTY + 人工 |
| 8 | 检查与摘要 | 错误/警告计数、逐条问题与跳转、配置概览（四类各自摘要）、向导进度 | P0 | golden + PTY |
| 9 | 表达式 | 校验诊断、变量规则、编译门禁、试算（模式/输入/结果/变量） | P0 | golden + PTY |
| 10 | C 代码页 | 实时只读 C、行号/高亮、搜索计数、复制、导出、错误阻断、空态 | P0 | 快照 + PTY |
| 11 | 汇编列表 | 按需构建、进度/失败/重试、`main.rst` 渲染（40 列弱化 + as251 着色 + C 锚点）、token 词表全量、复制/导出/重编 | P0 | golden + 快照 + PTY |
| 12 | 编译与产物 | SDCC 部署/指纹/缓存、Keil 发现/许可/重建、HEX/MAP/校验和、导出 HEX、日志/取消/失败提示 | P0 | golden + HIL + PTY |
| 13 | 烧录 | 设备检测、ISP 流程、进度/日志、重试、90s 超时、取消、错误分类、Linux udev 安装 | P0 | 协议 golden + HIL + PTY |
| 14 | 音频 | 调试提示音、音乐整曲/循环/琴键试听；无设备时降级 BEL 并提示 | P1（功能必须在，音质不承诺） | 人工 |
| 15 | CLI | `describe/validate/codegen`、stdout/stderr、退出码、`--out`、中文 UTF-8 | P0 | `assert_cmd` + golden |
| 16 | 文案与语义 | 全部界面/校验/错误/空态/日志中文，措辞一致；`parity/manifest.yaml` 登记 | P0 | 清单评审 + 快照 |
| 17 | 文件与导出 | `.pieproj`/`main.c`/`main.rst`/HEX 导出、路径输入、覆盖确认、失败提示 | P0 | PTY + 人工 |
| 18 | TUI 风格与可用性 | TUI 设计语言（§5.0）、主题、选中/焦点/错误非颜色信号、减少动态、无鼠标可用、80×24 | P0 | 快照 + 人工 |
| 19 | 非功能 | 启动 <500ms、80×24 可用、CJK 对齐、单实例、崩溃恢复、日志 | P0 | benchmark + PTY |

## 7. 数据兼容与跨语言一致性

### 7.1 `.pieproj` 格式（硬约束）

- 目标：**语义完全一致 + 保存结果字节一致**（同一文档在 Flutter 版与 TUI 版保存后 `SHA-256` 相同）。
- 逐项对齐：
  - 缩进 2 空格 + 末尾换行（UTF-8，中文不转义）；键序 = `toJson` 插入序（Rust 用有序结构/自定义序列化，不依赖 `serde_json::Map` 的默认序）。
  - 可选键省略规则：`id`、调试摩擦轮无 `duration_ms`、空 `action_tables`、空 `pin_notes`；固定引脚集合逐脚写出（含 `null`）；`friction_max_duties` 写已配置脚。
  - 数值：整数与浮点区分（如 `"parameter": -1.5`）；`num?.toInt()` 容错、布尔严格、非法结构报错（CLI 收成 exit 3）。
  - 时间：UTC ISO8601（`Z`，含毫秒/微秒位，按 Dart `toIso8601String`）；`copyWith` 自动刷新 `updated_at`。
  - 迁移：17→18 action_tables、18→19 direction→正负、19→20 pin_notes、20→21 移除 name、21→22 wrap、22→23 灵敏度；打开旧档自动写回 23，写回失败只提示。
  - 版本门禁文案逐字一致（“过旧/由更新版本创建”），`format_version` 始终写 23。
- 验收：9 份 fixture 打开→校验→保存→与 Dart 输出比对；随机/属性工程生成器（proptest）做往返不变式；`万轮` JSON 变异测试。

### 7.2 校验器

- 规则族、顺序、`stepId`、`fieldPath`、严重级别、文案逐字一致；约 208 条去重文案集中到 `pieblock-core/src/validator/messages.rs`（或 `locale/zh.rs`），禁止散落字符串。
- 输出顺序：先通用机器人规则，再按 kind；每族按字段/数组索引顺序追加，不排序（与 Dart 插入序一致）。
- 验收：对每个 golden 工程比对 `Vec<ValidationIssue>` 的完整 JSON（含顺序）；对 120 个随机合法变体 + 非法变体做差分；文案清单从 Dart 源提取成 golden，逐条锁定。

### 7.3 代码生成

- 单一 `main.c`；4 条 emit 路径；逐字节对齐（helper 只在用到时发射、固定顺序、SDCC 分支、浮点常量的 `f` 后缀/精度、整数除法/取模语义）。
- 风险点：`round()` 与 `clamp`、`toStringAsFixed(2)`、灵敏度 100% 时不得改变输出（版本 23 的承诺）、动作表/摩擦轮展开、表达式 helper 子集。
- 验收：350 份历史生成 C 逐字节；`verify_runtime` 的 27 变体 + 19 个运行时场景（Rust 侧用等价虚拟时钟/帧解码 harness 复跑）；6 个 HEX SHA-256 与 Flutter 构建一致（同 SDCC 版本/参数/工具链指纹）。

### 7.4 音乐与五线谱

- 单音裁决：排序键 `(start, pitch desc, id)`；组内 highest/lowest/nearest 平局链（pitch→duration→id）；打断接管与尾巴不恢复；`overlapCount` 端点合并；`segments()` 毫秒换算。
- MIDI：MThd/MTrk、running status、tempo/拍号/调号、note on/off FIFO、鼓通道剔除、导出 format 0 排序优先级、VLQ 边界、中文错误文案。
- 五线谱：调号拼写/谱号迟滞/时值/休止拆分/128×64 版面整数公式/22 字形/SoA 固件表；66 帧 SSD1306 golden 逐字节。
- 验收：现有 51+ 音乐专项用例转写；300 组随机配置对拍；MIDI 往返；五线谱 golden。

### 7.5 CLI 契约

- `describe` JSON、`validate` JSON（`ok/valid/project{kind,format,sourceFormat}/counts/issues`）、`codegen` 纯 C 或 `--out`、stderr 摘要、退出码 0–5、UTF-8。
- `project.format` = 23（当前版本），`sourceFormat` 为文件原版本；有 error 时 `validate` 退出 2 但 stdout 仍有完整 JSON；codegen 拒绝生成退出 2。
- 验收：9 个 CLI 契约用例 + 与 Flutter CLI 输出逐字节 diff；Windows/Linux 构建各自验证（CLI 与 TUI 共享 core，天然同源）。

### 7.6 工具链与 HEX

- 复用现有外部资源：`vendor/sdcc-toolchain`（155 文件/23MB，manifest 逐文件哈希）、`stc32g_sdcc`（`build_manifest.json` 的源顺序/编译/链接参数/库清单）、`stc32g/Libraries`；不重新编译工具链。
- 对齐：运行时部署（`.ready`、哈希校验、staging/rename、8 次退避、残留清理）、构建指纹 `flutter_build_v5|STC32G12K128|kind|compiler|compilerFingerprint|sourceSha256`、制品缓存与对象缓存、HEX/MAP 校验规则、宽松中文路径解码、`main_*.rst` 选取、取消语义。
- 验收：同一工程在 TUI 与 Flutter 版构建，HEX SHA-256 一致（6 个黄金样本 + 随机组合）；损坏缓存回退；中文用户名路径；取消后不残留进程。

## 8. 里程碑与工作量

> 以下为“1 名资深 Rust + 1 名 TUI/Rust”组合的估算；含测试但不含需求变更。单位：人周。

| 里程碑 | 目标 | 主要交付 | 验收门 | 估算 | 依赖 |
| --- | --- | --- | --- | --- | --- |
| **M0** | 技术验证 | ratatui 骨架（中文/宽字符/鼠标/粘贴/IME）、钢琴卷帘原型、hidapi 真机烧录原型、SDCC 调用+HEX/LST 对拍原型、crossterm/termina 对比报告 | 四项演示通过；锁定依赖版本 | 2–3 | — |
| **M1** | 领域内核 | 模型/JSON/迁移、校验器、代码生成、表达式、音乐/MIDI/五线谱、模板、CLI；golden 生成管线与对拍测试 | 9 fixture + 350 C + 6 HEX + 校验/文案全绿；CLI 契约全绿 | 9–12 | M0 |
| **M2** | 工具链与烧录 | 工具链部署/指纹/缓存、SDCC/Keil 构建、HEX/MAP、LST；HID 协议/传输/烧录状态机/udev | 真机烧录成功；HEX 与 Flutter 一致；取消/重试/异常路径通过 | 6–8 | M1 |
| **M3** | TUI 基座 | 应用循环、主题、布局/断点、键位/焦点、表单引擎、对话框栈、首页、文件浏览器、设置/最近项目、自动保存、PTY 测试框架 | 80×24/120×36 快照；首页→新建→打开→保存全流程 | 5–6 | M0 |
| **M4** | 向导表单 | 步兵 3 页、工程 4 页、调试 1 页、审查页；问题面板/跳转/阻断；动作行/动作表/执行器列表 | 21 步全流程可编辑；校验跳转一致；快照通过 | 10–12 | M3 |
| **M5** | 检查/代码/汇编/表达式 | 表达式检查与试算、C 代码页、汇编构建与 `main.rst` 渲染、词表详情、导出 | C/汇编与 Flutter 一致；构建进度/失败/重试；搜索/复制/导出 | 5–6 | M4 |
| **M6** | 音乐与音频 | 钢琴卷帘、选择/编辑/撤销、事件编辑、MIDI、播放/试听、灰显 | 卷帘专项用例通过；MIDI 往返；音频降级 | 6–8 | M4 |
| **M7** | 烧录页与部署 UI | 编译器选择、产物状态、设备区、进度/日志、安全确认、udev/Keil 对话框、导出 HEX | 真机编译→烧录→导出全链路 | 3–4 | M2/M5 |
| **M8** | 跨平台/发布 | Windows MSI/zip、Linux tar.gz/deb/udev、CI 矩阵、parity 清单 100%、用户文档、发布说明 | Windows/Linux 双平台冒烟；对等清单审计；1.0 验收 | 5–7 | 全部 |

**总工作量**：约 **50–64 人周**（含 20% 缓冲）。按 2 名开发 + 0.5 名测试/硬件并行，关键路径约 **33–38 周（8–9 个月）**；单人约 **12–15 个月**。M1 与 M3 可在 M0 后并行，M2/M6 可由第二人分担。

### 8.1 第一个迭代（建议 2 周）任务清单

1. 建 `tui/` workspace、CI（fmt/clippy/test/deny）、`rust-toolchain.toml`、许可证审计（`cargo-deny`）。
2. 写 `pieblock-core` 的模型骨架与 serde，先把 9 份 fixture 读进来（只读，不写校验/生成）。
3. 搭 ratatui 应用壳：中文标题/边框/宽字符对齐、Tab 焦点、鼠标点击、`Ctrl+Q`；录制 3 个 PTY 快照基线。
4. 实现钢琴卷帘只读原型（网格 + 光标 + 缩放），验证 120×36 下的可读性。
5. hidapi：枚举 VID 34BF/PID 1001 设备、读写一帧 `info`（真机），记录 Windows/Linux 差异。
6. 调 SDCC 构建一个模板工程：验证参数、HEX 校验、`main.rst` 读取；与 Flutter 产物 SHA-256 对比。
7. 输出《M0 验证报告》；语言已定为 Rust，不再做 Go 切换评估。

## 9. 质量保证与 CI

### 9.1 测试金字塔

| 层 | 内容 | 工具 | 门槛 |
| --- | --- | --- | --- |
| 单元/属性 | 模型/JSON、校验规则、代码生成、表达式、音乐裁决、MIDI、工具链指纹、HID 帧 | `cargo test`、`proptest` | 覆盖核心包 261 用例的等价语义；属性测试 ≥1 万轮 |
| 黄金对拍 | `parity/golden/**`：.pieproj 字节、校验 JSON、C 文本、CLI JSON、MIDI、五线谱 | 自研 `xtask parity` | 全部通过；任何 golden 变更需评审 |
| 组件快照 | 主题、表单、表格、卷帘、代码页、对话框、80×24/120×36 布局 | `ratatui::TestBackend` + `insta` | 每个屏幕 ≥1 张快照 |
| PTY 端到端 | 真实终端字节流：启动→新建→填字段→保存→生成→退出；键鼠脚本 | `portable-pty` + 自研 driver | Windows/Linux 各 10+ 场景 |
| 契约 | CLI stdout/stderr/退出码；HID 帧固定向量；文件原子写 | `assert_cmd`、固定向量 | 全绿 |
| 硬件在环 | SDCC 构建、Keil 构建、HID 烧录、udev 授权、导出 HEX | 自托管 Windows/Linux 机器 + 真板 | 每个发布候选跑一次 |
| 人工验收 | parity 清单、Windows/Linux 双平台冒烟、真实项目配置、音乐试听 | 验收脚本 + 2 名测试者 | 0 个 P0 缺陷 |

### 9.2 CI 矩阵

| 流水线 | 触发 | 内容 |
| --- | --- | --- |
| `tui-quality` | PR/push | `cargo fmt --check`、`clippy -D warnings`、`cargo test`、`cargo-deny`、文档链接检查（ubuntu，~5 分钟） |
| `tui-matrix` | PR/push | Windows（MSVC）、Linux（glibc）双平台构建 + PTY 快速集 + 快照 |
| `tui-golden` | PR/push | 用提交的 golden 跑全量对拍（不装 Dart，~3 分钟）；每周可选跑一次“Dart oracle 重新生成”任务，发现漂移即失败 |
| `tui-toolchain` | PR/标签 | 复用现有 SDCC 工具链构建/缓存；校验 `bundle_manifest.json`；TUI 构建产物 + 资源打包 |
| `tui-release` | tag `tui-v*` | Windows/Linux 产物、MSI/zip/tar.gz/deb、校验和、Release 正文（`docs/releases/tui-<版本>.md`） |
| `tui-hil` | 手动/夜间（自托管） | 真板烧录、6 个 HEX 对拍、Linux udev、Keil（Windows） |

### 9.3 硬件在环（HIL）清单

- Windows + 一块 STC32G 主控板：检测、info、编译并烧录、取消、断线重试、90s 超时。
- Linux + 同板：udev 未装/已装、pkexec 安装、hidraw 权限、写块 65 字节 report ID 语义。
- Keil：有许可证与无许可证两种状态；`TOOLS.INI` 备份/恢复；受限版日志识别。
- 中文用户名路径、杀软占用 `runtime`、只读目录等异常环境。

### 9.4 性能指标（发布门禁）

| 指标 | 目标 |
| --- | --- |
| 冷启动到首页可操作 | < 500 ms（SSD）；< 800 ms（HDD） |
| 常规按键到重绘 | < 16 ms；大表单滚动无卡顿 |
| 钢琴卷帘（4 分钟曲目、5000 音符）交互 | ≥ 30 fps 等价响应 |
| 内存占用（常规项目 + 代码页） | < 150 MB RSS |
| 大段汇编（5000 行）渲染/滚动 | < 50 ms 首帧 |
| 构建/烧录耗时 | 与 Flutter 版差异 < 5%（同工具链） |
| 安装包体积 | Windows < 40 MB（不含 SDCC 资源则 < 15 MB）；资源另计 |

### 9.5 代码质量门禁

- `unsafe` 仅限 HID/平台 FFI 薄层，逐处注释与审计；其余 crate `#![forbid(unsafe_code)]`。
- 中文文案不得散落：UI/校验/CLI 文案分别集中，CI 检查新增中文字符串必须出现在 `parity/manifest.yaml` 或消息表。
- 所有 P0 功能必须同时有键盘路径与 PTY 测试；鼠标路径允许手工验收。
- 任何与 Flutter 行为差异必须登记 `parity/known-deviations.md`，否则 CI 失败。

## 10. 分发、许可与运维

### 10.1 产物

| 平台 | 产物 | 说明 |
| --- | --- | --- |
| Windows x64 | `PIEBlock-TUI-<ver>-windows-x64.msi`、`-portable.zip` | MSI 安装到 `%LOCALAPPDATA%` 或 Program Files；zip 解压即用 |
| Linux x64 | `PIEBlock-TUI-<ver>-linux-x64.tar.gz`、`.deb` | tar.gz 顶层含 udev 规则与安装脚本；deb 含 `.desktop`（可选） |
| 通用 | `pieblock-cli`（Windows/Linux） | 与 TUI 同仓不同二进制；可独立分发 |
| 校验 | `SHA256SUMS`、CycloneDX SBOM | 与 Flutter 发布流程一致 |

### 10.2 安装布局

```text
PIEBlock-TUI/
├── pieblock-tui(.exe)
├── pieblock-cli(.exe)
├── data/
│   ├── assets/templates/*.pieproj
│   ├── pieblock_runtime/
│   │   ├── sdcc-toolchain/        # 复用 vendor 构建产物（逐文件哈希）
│   │   ├── stc32g_sdcc/           # build_manifest.json + 源码/工程
│   │   └── stc32g/Libraries/
│   ├── udev/70-pieblock-hid.rules # Linux
│   └── COPYING/COPYING3/LICENSE  # 许可文本
└── docs/README.md（可选）
```

资源定位顺序（与现有实现一致）：`PIEBLOCK_RUNTIME_ROOT` → `<exe>/data/pieblock_runtime` → 向上 8 层查找；缺失时报“发布包缺少 C251 工具链资源”（文案一致）。

### 10.3 许可证与合规

- **SDCC C251（GPL）**：随包携带 `COPYING`/`COPYING3`/上游 `README`，发布页面提供对应 `source_commit`（`912a589d…`）源码获取方式，保留完整源码归档；TUI 自身代码许可证需与团队确认（建议与 Flutter 版一致）。
- **字体**：TUI 不打包字体，使用终端字体，避免 OFL 分发义务；文档推荐等宽 CJK 字体。
- **图标/商标**：W.PIE/校徽资源版权归项目方；TUI 只输出文本词标，不使用 PNG。
- 第三方 crate：`cargo-deny` 检查许可证白名单；SBOM 随发布附上。

### 10.4 macOS（1.0 不纳入）

- 已确认 1.0 不构建/不测试/不发布 macOS；仓库与 Flutter 版现状也没有 macOS 前提（无 `macos/` 目录、SDCC 仅 Win/Linux 构建脚本、HID FFI 在 macOS 不支持）。
- 为未来保留可移植性：`pieblock-core` 不依赖平台；`hidapi`、音频、路径、进程管理通过 trait/feature 隔离；发布脚本按 target 参数化。
- 若未来单独立项，需要新增：macOS SDCC 工具链构建、IOKit hidapi 传输验证、签名/公证与 Gatekeeper 说明，工作量另估（约 4–8 人周）。

### 10.5 版本、日志与更新

- 版本：TUI 独立版本号（`0.1` 预览 → `1.0` 对等）；`.pieproj` 格式始终跟随 Flutter main（23）。发布说明写入 `docs/releases/tui-<ver>.md`。
- 日志：`<data>/logs/tui.log`（按天滚动，脱敏 token/路径可选）；`--diagnose` 生成诊断包（版本、OS、终端、设备、最近错误）。
- 更新：1.0 前手动下载更新；不内置自动更新，不联网（与 Flutter 版一致）。
- 与 Flutter 版共存：可同时安装；共享 `.pieproj`，不共享设置/缓存目录；文档提示“同一文件不要同时用两个版本编辑”。

## 11. 风险登记册

| # | 风险 | 概率/影响 | 应对 |
| --- | --- | --- | --- |
| R1 | 生成 C / 校验文案 / JSON 无法逐字节一致，导致“看起来能跑但固件不同” | 高/高 | M0 先做对拍原型；`parity/golden` 入 CI；M1 全量 350 C + 6 HEX + 208 文案；差异必须登记 |
| R2 | 钢琴卷帘/复杂表单在终端里交互不可用或体验差 | 高/中 | M0 卷帘原型 + 真实用户试用；键位优先、鼠标增强；必要时提供“简化视图 + 属性面板” |
| R3 | Windows 终端粘贴不可用（crossterm 0.29 限制） | 高/中 | `arboard` Ctrl+V + `termina` 后端可切换；M0 实测 Windows Terminal ≥1.25 与 conhost；长文本外部编辑器逃生口 |
| R4 | 中文 IME/宽字符在部分终端错位 | 中/中 | `unicode-width` + 双宽不变量测试；推荐终端清单；不做组合期实时校验；PTY 无法覆盖 IME，列入人工矩阵 |
| R5 | crossterm 0.30 破坏性升级、ratatui 拆 crate | 中/低 | 锁版本 + 自建事件抽象层；升级单独立项 |
| R6 | macOS 不在 1.0 范围（已确认） | —/低 | 不构建/不测试/不发包；保持核心无平台依赖与 trait 隔离，未来单独立项 |
| R7 | 内置 SDCC 体积/GPL 合规 | 中/中 | 复用现有 manifest 与许可文本；发布附源码获取方式；SBOM |
| R8 | HID 真机行为差异（Linux report ID、时序、重试） | 中/高 | 复用现有协议测试向量；HIL 每个 RC；错误文案与 Flutter 一致 |
| R9 | 表单/页面数量大导致 UI 工期超支 | 高/中 | 先建表单引擎与代码生成式字段表（字段元数据驱动），再逐页填充；M4 分批交付 |
| R10 | 双实现长期漂移（Flutter 继续演进） | 高/中 | 提交 golden 对拍 + 每周 CI 校验；约定“格式/代码生成变更必须同步 TUI golden”；明确维护责任人 |
| R11 | TUI 原生风格与用户预期不一致 | 低/中 | 用户已确认不要求与 Flutter 视觉统一；M0 出 2–3 套主题/布局草图供选择；`F1` 帮助说明交互 |
| R12 | Rust 人力不足/学习曲线 | 中/高 | 语言已确认 Rust；M0 结对/外部支持；模块边界清晰便于分工；不再切换语言 |
| R13 | 音频在 Linux 缺少 ALSA 头文件/无声卡 | 低/低 | 构建依赖文档；运行时检测失败降级 BEL；`--no-audio` |
| R14 | 大工程渲染与内存（超长 C/汇编、数千音符） | 低/中 | 视口裁剪、增量渲染、虚拟列表；benchmark 门禁 |
| R15 | 与 Flutter 版同时编辑同一 `.pieproj` | 低/中 | 原子写 + 文档提示 + 可选文件锁；冲突时以最后保存为准并提示 |

## 12. 待用户决策

> 已确认：语言 **Rust**；TUI 采用自身风格、**不逐项对齐 Flutter 视觉**；1.0 只做 **Windows/Linux**；**MCP 不做**。

1. **与 Flutter 版的关系**：长期并存（双实现），还是 TUI 逐步取代 Flutter（单实现）？这决定对拍与维护投入。
2. **最低环境**：Windows 10/11 是否都支持？只支持 Windows Terminal 还是也兼容 conhost？Linux 支持到哪些发行版（glibc 最低版本）？
3. **是否允许开发期 Dart oracle**：发布产物零 Dart 是硬约束；开发/CI 用现有 Dart 实现生成 golden 是否可接受？若不允许，需一次性冻结快照并接受人工维护成本。
4. **发行与品牌**：TUI 是否以 `PIEBlock-TUI` 独立发布？是否要求与 Flutter 版同版本号/同一下载页？是否需要 Windows 代码签名预算？
5. **数据目录**：TUI 独立数据目录（推荐，避免与 Flutter 设置互相覆盖）还是共享设置？
6. **人力/日期**：可投入几名开发、目标 1.0 时间；这决定 M0 之后是否缩减范围（如先做配置+生成+CLI，烧录与音乐延后）。
7. **视觉偏好**：TUI 风格是否有参考对象（如 lazygit/k9s/helix 风格）？没有则按 §5.0 默认设计执行。

## 13. 附录

### A. 关键参考文件

- 项目格式：`docs/reference/Flutter项目文件格式.md`（格式 23 与 17→23 迁移）、`packages/pieblock_core/lib/src/models.dart`
- 核心逻辑：`packages/pieblock_core/lib/src/{validator,code_generator,expression,music,midi_codec,staff_notation,staff_glyphs,staff_layout,staff_firmware_c,debug_cues}.dart`
- 工具链：`packages/pieblock_toolchain/lib/src/{builder,sdcc_build_plan,sdcc_runtime_deployer,sdcc_object_cache,artifact_repository,hex_validator,tool_output_text}.dart`、`stc32g_sdcc/build_manifest.json`、`vendor/sdcc-toolchain/bundle_manifest.json`
- 烧录：`packages/pieblock_hid/lib/src/{protocol,flasher,transport}.dart`、`packages/pieblock_hid/src/pieblock_hid*.{h,cpp}`、`linux/udev/70-pieblock-hid.rules`
- 平台层：`lib/src/platform/**`、`lib/src/{deploy,asm_preview,expression_check}_controller_native.dart`
- UI：`lib/src/{home_screen,wizard_screen,music_editor,asm_hover}.dart`、`lib/src/wizard/**`、`lib/src/design/**`
- 测试基准：`packages/pieblock_core/test/`、`packages/pieblock_core/tool/verify_runtime.dart`、`test/widget_test.dart`、`test/music_*_test.dart`
- CLI：`packages/pieblock_core/bin/pieblock.dart`、`docs/guides/PIE-Block命令行工具.md`
- 打包/CI：`.github/workflows/{windows,linux}.yml`、`tools/{prepare_sdcc_toolchain.*,build_sdcc_*,package_flutter_*}`

### B. 依赖版本锁定表（M0 时更新）

见 §3.3。TUI 工程提交 `Cargo.lock`，CI 使用 `--locked`；Rust 工具链版本写入 `rust-toolchain.toml`。

### C. `parity/manifest.yaml` 示例

```yaml
screens:
  - id: home
    source: lib/src/home_screen.dart
    tests: [pty/home_open_save, snapshot/home_120x36]
  - id: wizard.engineer.mappings
    source: lib/src/wizard/wizard_pages_engineer.dart
    fields:
      - path: modes.0.actions.0.input_kind
        control: select
        tests: [pty/engineer_action_expr]
      - path: modes.0.actions.0.expression
        control: text
        tests: [pty/engineer_action_expr]
    dialogs: [pin_conflict, delete_action]
  - id: wizard.music
    source: lib/src/music_editor.dart
    fields: [music.notes, music.tempo_events, music.time_signature_events]
    tests: [pty/music_select_copy, pty/music_midi_import]
exceptions:
  - id: images.logo
    replacement: text-wordmark
    approved_by: TBD
```

### D. 术语

- **golden**：由 Flutter 实现生成的期望结果快照，提交到 `parity/golden/`，Rust CI 无需 Dart 即可对拍。
- **PTY 测试**：在伪终端中启动真实 TUI，注入键鼠字节流并断言屏幕内容。
- **HIL**：Hardware-in-the-Loop，真实主控板/工具链在环测试。

### E. 修订记录

| 日期 | 版本 | 说明 |
| --- | --- | --- |
| 2026-11-18 | v0.1 | 首版计划；基线 `a9143e6`（1.8.0+14，格式 23），排除已下架 MCP |
| 2026-11-18 | v0.2 | 按确认修改：语言定为 Rust；TUI 原生风格、不逐项对齐 Flutter；1.0 只做 Windows/Linux（macOS 不纳入） |



