# PIE-Block TUI 复刻进度

> 计划：[`TUI复刻实现计划.md`](TUI复刻实现计划.md)。基线 `main@a9143e6`（1.8.0+14，`.pieproj` 格式 23）。
> 本文件随里程碑推进更新；每完成一项即提交推送。

## 状态

**当前：M1 领域内核 + CLI ✅；M2 工具链 + HID 进行中；M0 需人工/硬件验证项待补**

## 里程碑清单

| 里程碑 | 状态 | 说明 |
| --- | --- | --- |
| M0 技术验证 | 🟡 收尾 | Rust 工具链、workspace、M0 演示壳、表单/卷帘原型、单元测试、CI 已就绪；待：真实终端键鼠/IME 验证、hidapi 真机、SDCC+HEX 对拍、卷帘体验评审 |
| M1 领域内核 + CLI | ✅ 完成 | 模型/迁移/校验/表达式/四类 C 生成/音乐时间轴/MIDI/五线谱固件表/CLI validate·codegen·propose 全部移植，golden 逐字节对拍（模型 13、校验 24、表达式 60+、codegen 17、CLI validate/codegen 42、CLI propose 7、MIDI 3+往返）；五线谱布局渲染留待 M6 |
| M2 工具链 + HID | 🟡 进行中 | 已完成：Intel HEX 解析、主控板应用区校验、SDCC HEX/MAP 布局校验（13+13+6 golden）、HID 帧/报告/块映射、烧录状态机（9 场景对拍）、运行时部署（staging/校验/rename/退避/清理）、目标文件缓存、SDCC 构建计划与中断声明头、**原生 hidapi 传输（Windows/Linux，含取消标志）**、**FirmwareBuilder SDCC 全流程（指纹→部署→逐源编译/对象缓存→共享库→链接→HEX/MAP 校验→列表文件→产物入库）与产物仓库**、**烧录 worker（HEX 哈希校验/90s 硬超时/取消/事件通道）与 Linux udev 规则检测/安装**；待：Keil 构建、真机烧录 |
| M3 TUI 基座 | 🟡 进行中 | 主循环已接线：首页（最近项目/快捷键）↔ 工程概览 ↔ 文件浏览器 ↔ 设置；新建工程（类型选择 + 路径编辑）、打开/保存（Ctrl+S/F5）、500ms 自动保存、主题/编译器/Keil 路径/引导开关持久化、鼠标滚轮；`--demo` 保留 M0 演示壳。待：PTY 全流程测试、真终端人工验收（Windows/Linux 键鼠/中文）与工程页接入 M4 表单 |
| M4 向导表单 | 🟡 进行中 | 已移植通用表单引擎（数字/小数/文本/下拉/开关、焦点与编辑、范围校验、写回 `ProjectConfig`、渲染）、「遥控器与底盘」页与步兵「云台与拨弹机构」「控制与摩擦轮」页；向导已接入工程页（Enter 进入、PgUp/PgDn 翻页、Esc 保存返回、变更即 500ms 自动保存）；待：执行器列表/动作行/动作表等列表编辑、工程与调试页、审查页/问题跳转 |
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

## 下一步（M2 继续）

1. hidapi 原生传输：Windows `windows-native` / Linux `linux-static-hidraw`，设备枚举、打开/读/写/取消；真机烧录验证（需主控板）。
2. SDCC 运行时部署：`.ready`、哈希校验、staging/rename、退避与残留清理；工具链 bundle 指纹。
3. SDCC/Keil 构建：构建指纹、对象/产物缓存、HEX/MAP/LST 解析与导出；HEX SHA-256 与 Flutter 产物对拍（需 SDCC 与硬件）。
4. udev 规则检查/安装与 `HidFlasher` 的取消/90s 超时 worker 封装。

## M1 已完成

- 开发期 Dart golden 生成器：`tui/parity/tools/bin/export_model_goldens.dart`（读取 9 份 fixture + 4 份模板，输出迁移后的 `ProjectDocument.toJson()`）。
- 13 份模型 golden：`tui/parity/golden/model/*.json`；Rust 侧对每份输入读取→迁移→写出，**逐字节**等于 Dart 生成的 wrapper（`tests/model_golden.rs`）。
- `pieblock-core::model`：4 种 config、全部枚举、`Remote/Chassis/Pwm/Axis/Debug/Music/ActionMapping/ActionTable/Mode` 模型，以及 17→23 迁移（方向折负、`wrap`/灵敏度/引脚备注缺省、`name` 忽略等）。
- `pieblock-core::document`：格式版本门禁（17–23，中文错误文案逐字一致）、向导进度、`to_pretty_string`（2 空格 + 末尾换行）、golden wrapper。
- `pieblock-core::ids`：Dart 形态的 UTC ISO8601 与 `microsecondsSinceEpoch` 风格 id。
- `pieblock-core::json`：Dart 宽容语义的数值截断、字符串/布尔/数组读取、`string_enum!` 宏、`ParamNum`（整数/小数参数）。
- `pieblock-core::validation`：公共机器人规则、步兵专属规则、**工程专属规则（PWM 角色与频率、舵机中位/两侧限幅、模式数量与切换键、动作行控制方式矩阵、表达式/变量规则、按键动作表、摩擦轮安全控制、多行覆盖警告）**、调试工程完整规则；19 份校验 golden 中调试/步兵/工程完整列表逐条一致（仅音乐规则待移植）。- `pieblock-core::expression`：表达式解析/类型检查（诊断文案与 UTF-16 偏移一致）、求值（除零→0、负数开方→0、Dart 取模）、C 代码发射（helper 调用与转换格式一致）、运行时 helper 代码、变量名规则、工程模式试算（`EngineerPreview`）；表达式 golden 覆盖 60+ 用例、6 组运行时 helper、变量名校验及工程模板逐模式试算，全部与 Dart 一致。
- `pieblock-core::model`：补 `EngineerPinCapabilities`（工程引脚能力）、`Friction` 常量与油门映射、`PwmGroupConfig::role_of/is_servo_pin`，供校验与后续代码生成共用。
- `pieblock-core::codegen` + `debug_cues`：调试/步兵/工程/**音乐** C 代码生成逐字节对拍（音乐含 128 音频率表、SDCC 五线谱固件表、Keil 蜂鸣器片段与播放循环）；生成前校验门禁与 Dart 文案一致；**17 份 codegen golden 全部逐字节一致**。调试提示音曲谱常量与步序映射已移植（供固件与后续试听共用）。
- `pieblock-core::staff_*`：五线谱模型（调号拼写/谱号分配/时值选择/休止拆分/临时记号/barTicks/毫秒时长）、22 个字形的 1bit 点阵、固件 C 数据表发射；音乐校验的五线谱固件预算提醒已补齐。`staff_layout` 渲染留待 M6 音乐页。
- `pieblock-cli`：`validate`/`codegen`/`propose` 已接领域内核，stdout/stderr/退出码与 Dart CLI 逐字节对拍（21 份工程 × validate/codegen = **42 个用例全部一致**；propose 7 个用例：成功/强制覆盖/已有提案/新增校验错误/类型不一致/空改动/候选缺失，仅时间戳归一化）；版本不兼容、校验失败、`--out` 写文件等路径一致。21 份 CLI 用工程快照落在 `tui/parity/cli/projects/`。
- `pieblock-core::proposal`：提案创建（类型一致/往返核对/只禁止新增 error/非空 diff）、编码（2 空格缩进 + 末尾换行逐字节）、`fromJson` 校验（schema/kind/baseSha256/document）、SHA-256、`.proposed` 路径规则；golden 9 个创建用例 + 5 个往返/校验用例。已知差异：候选字段标量类型错误在 Dart 端抛 `TypeError`（invalid_document），TUI 宽容解析可能归类为 `unroundtripped_value`，两者都拒绝提案且给出字段路径，待后续补 Dart 类型文案仿真。
- `pieblock-core::music` + 音乐校验：重叠裁决（同 tick 选音、打断/策略比较、已打断不恢复）、发声区间、重叠处数、tick→微秒（含变速）、蜂鸣器片段合并；音乐校验覆盖调号/PPQ/音符 ID 与音高/时值/速度事件/拍号/重叠提醒/片段数/总时长。校验 golden 扩到 **24 份**（音乐 5 份完整列表逐条一致；仅五线谱固件预算提醒待 staff 模块移植）。
- `pieblock-core::midi`：MIDI Format 0/1 解析（running status、变速/拍号/调号 meta、鼓通道过滤、VLQ、容错文案）、写回（Format 0 单轨、调号/速度/拍号/音符事件排序、轨道名 UTF-8）、`select_track` 生成音乐配置；golden 覆盖 3 份写出字节逐字节 + 往返解析结构 + running status 手工样本 + 5 类错误文案，全部一致。
- `pieblock-core::ids`：补上 Dart `toIso8601String` 的规则——微秒为 0 时 3 位小数，否则 6 位。

## M2 已完成（进行中）

- `pieblock-toolchain::hex`：Intel HEX 解析（扩展地址类型 2/4、记录类型 1/3/5、空行、长度/校验和/非法字符/类型错误文案）与应用区布局校验（FE0000 用户区、FF0000 向量区、LJMP 复位向量）；SDCC HEX/MAP 链接布局校验（HOME/CSEG/XSEG/DSEG 等区域与启动符号）。Dart golden 覆盖 13 个解析、13 个应用区、6 个 MAP 用例，全部逐字节/逐文案一致。
- `pieblock-hid::protocol`：帧编码、1ms 报告间隔、65 字节报告拆分、HEX→块映射（用户区首块 `0x32`、后续 `0x12`、向量区 `0x02`、空白补零）、ACK 校验与无响应分类。固定向量 golden 与 Dart 一致。
- `pieblock-hid::flasher`：连接→擦除→分块写入（同址重发 3 次、50ms 退避）→复位状态机，含进度事件、写入失败/命令异常/帧头异常、`info` 探活与「仍在 ISP / 已掉线」操作指引。9 个脚本化场景的事件序列、结果文案、写出报告、关闭状态全部与 Dart 一致。
- 生成器：`tui/parity/tools/bin/export_m2_goldens.dart` → `tui/parity/golden/m2/m2.json`。
- `pieblock-toolchain` 运行时与构建编排：`file_ops`（瞬时占用重试/递归复制）、`models`（构建请求/事件/指纹/产物 JSON/结果）、`sdcc_runtime_deployer`（唯一暂存目录→SHA-256 校验 bundle→`.ready` 指纹→8 次退避 rename，残留清理与占用提示）、`sdcc_object_cache`（v1 缓存键、原子写、大小+SHA-256 复用校验、损坏回退未命中、旧指纹清理）、`sdcc_build_plan`（`build_manifest.json` 源码组/工程映射/编译链接参数、`main_*.rst` 中断声明头去重排序输出）。行为测试覆盖部署复用/损坏拒绝、缓存往返/损坏、计划与中断头。
- `pieblock-hid::native`：Windows `hidapi` `windows-native` / Linux `linux-static-hidraw` 传输——按 VID/PID 枚举、`open_path`、写报告（校验完整长度）、`read_timeout` 分片等待与跨线程取消标志、关闭；无设备时枚举为 0，真机烧录待硬件验证。
- `pieblock-toolchain::builder` + `artifact_repository`：SDCC 构建全流程——构建指纹（schema/MCU/工程/编译器指纹/源码哈希）、运行时部署→固件清单解析→逐源编译（`--include` 中断头）→目标文件缓存命中/写回→`stc32g_shared.lib`→链接（`-L output -L lib -o hex`）→SDCC HEX/MAP 布局校验→`main_*.rst` 列表读取→HEX 应用区校验→产物入库（LF 规范化 SHA-256、`build.log`、`artifact.json`）；含 `findFresh` 校验、`markFlashed`、过期/超限清理。`ProcessRunner` trait 隔离进程调用（真实 `SystemProcessRunner` 流式日志/取消，测试注入假编译器）。测试覆盖成功构建、对象缓存复用（第二次只重编 main）、HEX 校验失败拒绝、产物指纹/日志。
- `pieblock-hid::worker`：烧录任务线程——HEX 存在 + LF 规范化 SHA-256 比对 → 应用区布局校验 → 传输层工厂（接收取消标志）→ 烧录状态机；90 秒硬超时/主动取消置位标志并改写结果为「烧录超过 90 秒，已自动取消 / 已取消烧录」；事件 mpsc + 结果通道，`cancel()`/`try_recv_event()`/`wait()`。测试覆盖成功、超时、HEX 哈希不匹配。
- `pieblock-hid::udev`：内嵌 `70-pieblock-hid.rules` 与安装脚本；`is_installed`（非 Linux 恒 true）、`pkexec /bin/sh -c` 安装（规则 base64 经 `$1` 传入，不落临时文件），退出码映射 0 成功 / 10 无 udevadm / 126 取消授权 / 127 未授权，pkexec 缺失与 2 分钟超时分类；`UdevCommandRunner` 可注入测试。base64 与退出码映射测试通过。
- 待硬件：真机烧录与 SDCC 构建 HEX 对拍（需要主控板与 SDCC 环境）。

## M3 已完成（进行中）

- `pieblock-tui::settings`：应用设置（主题 system/light/dark、最近项目、编译器、Keil 路径、两个引导开关）与 Flutter `settings.json` 字段对齐；读取容错、最近项目新/旧格式（`{path,kind}` / 纯路径）解析、最多 8 条、`load_cleaned` 清理已不存在的项目并补读类型；同目录临时文件 + rename 原子写；设置写失败不打断应用。
- `pieblock-tui::session`：`ProjectSession` 新建（可选模板只替换配置）/打开/保存；打开时旧格式（17–22）自动迁移并写回当前格式（写回失败仍可打开并给提示）；`save_now` 使用原子写；`update_config` 更新时间戳并置「保存中」；文件名显示名、类型补读。
- `pieblock-tui::workspace`：工作区把设置、最近项目、当前工程串起来；`create/open` 自动记录最近项目并持久化设置；`update_config` + `Autosave`（500ms 防抖）`tick()` 到点自动保存；主题循环、保存状态/标题/错误文案；测试覆盖新建/编辑/自动保存/主题持久化/打开失败。
- `pieblock-ui` 已有主题/布局/焦点基础；新增 M3 页面组件：`screens` 提供首页（品牌区/快捷键/最近项目列表，缺失文件警示、选中态）、文件浏览器（路径栏、目录/`.pieproj` 过滤、隐藏项跳过、循环选择、进入目录/打开工程/返回上级状态机）、设置页（分组行/说明/选中态）、通用状态栏与对话框。`TestBackend` 测试覆盖 80×24/120×36 首页（有/无最近项目）、浏览器渲染与 5 类导航动作、设置页；下一步接入 TUI 主循环（首页↔浏览器↔设置↔工程）。
- `pieblock-tui::home_shell`：默认启动的 M3 交互外壳——首页（最近项目 ↑↓/Enter、N 新建、O 打开、S 设置、Q 退出、滚轮选择）→ 新建工程浮层（四种类型选择 + 路径输入，创建后进入工程概览并自动记录最近项目）→ 工程概览（类型/路径/格式/保存状态/向导步数，Ctrl+S 或 F5 保存）→ 文件浏览器（进入目录/打开工程/上级/返回）→ 设置页（主题/编译器/Keil 路径输入/引导开关，Enter 切换并立即持久化）。`--demo` 仍可启动 M0 演示壳。测试覆盖首页渲染、新建工程全流程（文件落盘+最近项目）、设置持久化、浏览器打开工程。

## M4 已完成（进行中）

- `pieblock-ui::form`：数据驱动表单引擎——`FieldKind`（Number/Decimal/Text/Choice/Toggle）、字段取值/写回闭包、焦点 Tab/↑↓、左右调整（数字步进/下拉循环/开关翻转）、Enter 进入编辑（数字/文本）、范围与字符数校验（中文错误文案）、编辑提交写回 `ProjectConfig`、脏标记；渲染含页面标题/说明、字段列表、选中高亮、字段帮助与按键提示。
- `pieblock-ui::pages::remote_page`：「遥控器与底盘」页与 Flutter 字段/范围/文案对齐：通道号 0–125、摇杆死区 0–2047、四轮 IO 与方向（未设置/正转/反转）、普通/冲刺速度 0–10000、转向灵敏度 10–200%、冲刺与反转开关；工程类型额外提供底盘启用开关（关闭禁用引脚占用）。
- 步兵页：`infantry_mechanism_page`（拨弹 IO/方向、Yaw/Pitch 灵敏度 10–200% 步长 5）与 `infantry_controls_page`（方向键用途、拨弹模式、拨弹/反转拨弹键、拨弹速度 duty、单发时长 ms、摩擦轮模式/按键/加减速键、P64/P66 最大 duty、油门步长）。执行器列表与动作行/表编辑留待下一轮。
- 主循环接线：工程概览 Enter/E 进入向导；PgUp/PgDn 切换页面（首页前翻/末页后翻即保存返回）；表单变更立即写入 `Workspace` 并触发 500ms 自动保存；Esc 保存并返回工程概览；测试覆盖「新建步兵 → 向导改通道 55 → 翻页 → 返回 → 文件已保存」。
- 测试：字段数量/顺序、数字编辑写回与越界拒绝（保留编辑态）、开关与下拉循环、数值上限钳制、翻页动作、工程底盘开关、步兵页字段编辑、80×24/120×36 渲染、向导端到端；fmt/clippy/全量测试全绿。



```powershell
cd tui
.\run.ps1                  # 自动定位 cargo；默认进入 M3 交互外壳（首页/工程/浏览器/设置）
.\run.ps1 -NoMouse          # 关闭鼠标捕获
.\run.ps1 -Demo             # M0 演示壳（三栏布局/表单/钢琴卷帘原型）
```

- 调试页：`debug_tests_page` 按固定 `DEBUG_PINS`（P00–P07/P20/P21）生成 10×4 字段（启用、驱动类型 电机/舵机/摩擦轮、输出值 -10000–10000、时长 0–60000ms），表单引擎列表自动滚动；调试工程进入向导即可编辑，`wizard_pages(Debug)` 返回该页。

- 审查页：工程概览按 R 进入「问题审查」，读取 `pieblock_core::validate` 的完整问题列表（错误 ✖/警告 ⚠、字段路径、文案、计数），Enter 在已移植里定位相同 `field_path` 的向导页与字段并跳转，找不到时明确提示「该问题位于尚未移植的页面或列表项」；测试覆盖问题列表渲染与跳转/返回。
