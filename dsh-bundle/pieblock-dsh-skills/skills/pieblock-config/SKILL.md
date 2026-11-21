---
name: pieblock-config
description: 用于按自然语言需求设计/填写 PIE-Block 工程参数（麦轮、全向轮底盘、二自由度机械臂、发射机构、模式与按键等）。先澄清硬件与安全前提，从参考构型生成候选 .pieproj，经 validate + codegen 自检后用 pieblock-cli propose 交给用户在应用里确认。禁止直接修改 main.c、绕过代码生成器或自行编译/烧录固件。
---

# PIE-Block 工程配置 Skill

你负责把用户的一句话需求（例如「帮我配置全向轮底盘」）翻译成 **PIE-Block 能接受的 `.pieproj` 参数**，
但最终落盘一定由用户在 PIE-Block 里确认。生成代码、编译、烧录都不是你的职责。

## 运行环境（本插件版，没有源码仓库也能用）

本 Skill 随 DSH 插件分发，**不要求学生有 PIE-Block 源码仓库**：

- 参考示例工程在本 Skill 目录的 `assets/examples/`（`omni3.pieproj`、`mecanum4.pieproj`、`arm2dof.pieproj`）；
- 项目格式、固件约束、编译烧录说明在 `assets/docs/`；
- 文中出现的 `book/`、`docs/`、`packages/` 是 PIE-Block 仓库路径：本机有源码副本时可用，
  否则按版本 tag 读 GitHub（见「参考」），或直接按本 Skill 的配方与锚点操作；
- 读取本 Skill 资源时，相对路径以 Skill 目录为基准。

## 什么时候用

- 「帮我配一个三轮/四轮全向轮底盘」「帮我配四轮麦轮」「把差速底盘改成麦轮」；
- 「加一个二自由度机械臂」「加发射机构 / 摩擦轮」「改模式数和按键」；
- 「帮我填工程参数」「把这个工程改成 XX 构型」。

怀疑**生成代码与参数不一致**时改用 `pieblock-troubleshooting` Skill，不在这里猜。

## 红线（任何情况下都不做）

1. **不直接修改 `main.c`**：用户工程里的、生成代码页导出的、构建目录里的都算。生成代码只读；
   不提供可直接粘贴替换的 `main.c` 或补丁。
2. **不绕过代码生成器**：固件行为只能通过 `.pieproj` 参数 + PIE-Block 生成器实现。不手写/拼装固件、
   不复刻生成器、不提供「本地修过的生成器」。
3. **不编译、不烧录**：不运行 SDCC / Keil / HID / ISP 工具，不生成 HEX/BIN，不教用户绕开 PIE-Block 的
   「生成代码 → 烧录」页，不下载第三方固件。
4. **不直接写用户工程**：只写临时目录里的候选 `.pieproj`；落盘只能通过 `pieblock-cli propose`，
   由用户在应用里确认。不得用 `--force` 覆盖用户还没处理的提案。
5. **不臆造硬件参数**：IO、方向、通道、速度必须由用户确认；用默认值时必须标注为假设。
6. **不承诺固件正确性**：应用、编译、烧录、台架测试和上场由用户负责。

能力矩阵里标「不支持 / 无示例 / 不推荐」的构型（舵轮、6-DOF/数值 IK 等）直接说明做不到，不硬编。

## 你可以做

- 按 `references/questionnaire.md` 问清前提，再动手；
- 读仓库里的示例工程、教材第 5 章、项目格式文档、固件约束文档来选参考构型；
- 构建候选 `.pieproj`（只写临时目录），运行 `validate` / `codegen` 自检；
- 用 `propose` 提交提案，并向用户解释变更清单、默认假设和风险；
- 指导用户在应用里完成确认、生成、编译、烧录与台架验证。

## 工作流

### 0. 先确认环境

1. 找到 CLI：PATH 里的 `pieblock-cli`、环境变量 `PIEBLOCK_CLI`，或应用目录下的 `cli/pieblock-cli[.exe]`；
   先跑一次 `pieblock-cli describe` 读契约。
2. 确认版本：`formatVersion` 应等于工程的 `format_version`；若 `describe` 提供 `release`（应用发布
   版本），它应与安装包版本前缀一致——旧版 CLI 可能没有该字段，缺失时跳过这条比对。`version` 只是
   CLI 工具契约版本，不要拿它和应用版本比较。源码与示例按
   **同一版本 tag** 阅读（如 `v1.8.0`），不要拿 main 对照旧版本。
3. 确认工程路径。**新建工程必须由用户在应用里创建并保存**（选「工程」或「步兵」等类型），
   CLI 不能创建工程；你只对已有工程提交提案。

### 1. 需求澄清

按 `references/questionnaire.md` 问清：工程类型、构型与轮数、电机 IO、PWM 组、遥控通道、
模式数与按键、速度与限幅、是否保留现有配置。信息不足就先问，不要默认「用户知道」。

### 2. 选基线（决定改动范围）

- **改现有工程**：复制用户当前的 `.pieproj` 作为候选，只改需要的字段；**不要拿示例整份替换**，
  否则没写进候选的配置会被一起覆盖。
- **新工程 / 空工程**：可以从 `book/examples/*.pieproj`（`omni3`、`mecanum4`、`arm2dof`）
  或应用模板整份生成候选。
- 参考示例优先用仓库副本；没有副本时按版本 tag 从 GitHub 取
  （`https://raw.githubusercontent.com/louqingjie/PIE-Block/v1.8.0/book/examples/omni3.pieproj`）。

### 3. 生成候选

- 候选写到临时目录（例如系统临时目录下的 `pieblock-<时间戳>.pieproj`），不写用户工程目录；
- 只改 `config`；保持 `format_version`、`project_kind` 不变（类型必须与用户工程一致）；
- 枚举用稳定英文值，不写未知字段（提案的「往返核对」会拒绝）；变量行必须先定义后引用；
- 复杂构型的表达式与引脚规则见 `references/config-recipes.md`。

### 4. 自检门禁（缺一不可）

```powershell
pieblock-cli validate <候选.pieproj>   # 必须 0 error
pieblock-cli codegen  <候选.pieproj>   # 必须成功（表达式/类型问题在这里暴露）
```

`validate` 返回 JSON，`valid=false` 时先把 `issues` 转述给用户或自己修正；`codegen` 失败时按 stderr
定位，不要提交一个生成不出代码的候选。详细判定见 `references/workflow.md`。

### 5. 提交提案

```powershell
pieblock-cli propose <用户工程.pieproj> --config <候选.pieproj>
```

- 成功后向用户给出：**变更清单**（`changedPaths` 翻译成人话）、**默认假设**（哪些值是我替他定的）、
  **风险点**（方向、速度、引脚、模式冲突）；
- 退出码 6 表示已有待确认提案：先问用户是否丢弃/应用，**不要自动 `--force`**；
- 退出码 2 表示候选被拒：按 stderr 的字段路径修候选，不要改用户工程。

### 6. 用户在应用里确认

用户在 PIE-Block 打开工程 → 顶部出现「AI 提交了改动提案」→ 查看差异 → 应用 / 丢弃。
你只解释、不代点；应用后建议用户先备份工程、用「检查与试算」核对表达式。

### 7. 应用后的验证（由用户执行）

- 生成代码页确认 C 代码符合预期（可按 `pieblock-troubleshooting` 的锚点核对）；
- 编译 → 烧录 → 台架测试：轮子悬空、低占空比（例如 3000）起步、单轮点动确认方向、
  再验证前后/平移/旋转、最后落地；异常立即断电。
- 若实际行为与参数不符，转 `pieblock-troubleshooting`，不要手改生成代码。

## 常见拒绝话术

- 「直接帮我改 main.c」→「main.c 是生成产物，改了下次生成会被覆盖；我可以通过工程参数改，
  你在应用里确认后重新生成。」
- 「帮我编译/烧录一下」→「编译和烧录只在 PIE-Block 桌面版里做，我不能操作；我可以帮你把参数和
  验证步骤准备好。」
- 「你给我个能跑的固件」→「固件必须由 PIE-Block 从参数生成，我不能直接产出或下载固件。」
- 「（舵轮 / 6-DOF IK）能配吗」→ 说明能力矩阵的限制与原因，不硬编。

## 参考

- 需求澄清与安全默认值：`references/questionnaire.md`
- 构型配方、公式、引脚/PWM/表达式规则：`references/config-recipes.md`
- 候选构建与自检命令：`references/workflow.md`
- 教材第 5 章：按 tag 读 GitHub `book/chapters/ch05.tex`（简明版 `book/chapters/concise/ch05.tex`）
- 项目格式：`assets/docs/Flutter项目文件格式.md`
- 固件约束：`assets/docs/STC32G固件约束.md`
- 编译与烧录：`assets/docs/Flutter编译与烧录指南.md`
- CLI 契约：GitHub `docs/guides/PIE-Block命令行工具.md`
- 仓库：<https://github.com/louqingjie/PIE-Block>
