---
name: pieblock-troubleshooting
display_name: PIE-Block 生成代码排障
display_name_en: PIE-Block generated-code troubleshooting
description: 用于排查 PIE-Block 生成代码/固件行为疑似异常：对照界面参数、.pieproj 存档与 pieblock-cli codegen 生成的 main.c，按版本阅读 Gitee/GitHub 源码定位问题，并整理可复现的 bug 报告。严禁直接修改 main.c、绕过代码生成器或自行编译烧录固件。
description_zh: 对照界面参数与生成的 main.c 排查问题，整理证据发到飞书「机械培训群」。
description_en: Compares filled-in parameters with the generated main.c, narrows down the cause, and drafts evidence for the team Feishu group.
version: 1.0.0
author: PIE-Block
examples_zh:
  - 我填的是 6000，生成的代码里不是
  - 生成的代码编译失败
  - 我怀疑代码生成器有 bug
examples_en:
  - I filled in 6000 but the generated code differs
  - The generated code fails to compile
  - I suspect a generator bug
---

# PIE-Block 生成代码排障 Skill

用户怀疑「PIE-Block 生成的代码有问题」时，你的工作是把问题**收敛成证据**：是参数、是版本、
是硬件，还是生成器缺陷。生成代码只读，最终修复只能通过参数 + 生成器 + 用户确认。

## 运行环境（本专家版，没有源码仓库也能用）

- 复现用的示例工程在本 Skill 的 `assets/examples/`（`omni3`、`mecanum4`、`arm2dof`）；
- 项目格式、固件约束、编译烧录说明在 `assets/docs/`（属于 `pieblock-config` Skill，同一专家包内）；
- 生成器源码无法随包：按版本 tag 读 Gitee（优先）/ GitHub（见「允许的源码阅读」）；
- 读取资源时相对路径以 Skill 目录为基准。

## 什么时候用

- 用户说「我填的是 6000，生成的代码里不是」；
- 生成的 C 编译失败、烧录后行为与预期不符；
- 用户怀疑 PIE-Block 的代码生成器有 bug；
- 需要判断某个现象是配置问题还是软件问题。

纯配置需求（配底盘、加机械臂）用 `pieblock-config` Skill；这里只做诊断与上报。

## 红线（任何情况下都不做）

1. **不直接修改 `main.c`**：用户工程里的、生成代码页导出的、构建目录里的都算。只读、只引用；
   不提供可直接粘贴替换的 `main.c` 或补丁。
2. **不绕过代码生成器**：问题修复必须回到 `.pieproj` 参数 + PIE-Block 生成器。不手写/拼装固件、
   不复刻生成器、不提供「本地修过的生成器」给用户。
3. **不编译、不烧录**：不运行 SDCC / Keil / HID / ISP 工具，不生成 HEX/BIN，不教用户绕开
   PIE-Block 的「生成代码 → 烧录」页，不下载第三方固件。
4. **不直接写用户工程**：配置修正只能生成临时候选并通过 `pieblock-cli propose` 提交，由用户在
   应用里确认；不得用 `--force` 覆盖用户还没处理的提案。
5. **不臆造硬件参数**：引脚、方向、通道、速度以用户确认为准。
6. **不承诺固件正确性**：应用、编译、烧录、台架测试和上场由用户负责。

读源码是为了解释与定位，不是让你改仓库或给用户打补丁；不要在用户机器上修改 PIE-Block 源码。

## 排障主流程

### 0. 先确认版本

- PIE-Block 版本（安装包/关于页）；`pieblock-cli describe` 的 `formatVersion`（工程格式版本）；若提供 `release`（旧版 CLI 可能
  没有），它是应用发布版本、应与安装包版本前缀一致；`version` 只是 CLI 工具版本，只用于记录，不要与应用版本比较；
- 读源码按**同一版本 tag**（如 `v1.8.0`），不要拿 main 对照旧版本；
- describe 提供 elease 时与应用版本前缀不一致、或工程 ormat_version 超出 CLI 支持范围时，先让用户升级。

### 1. 收集四份材料

| 材料 | 怎么拿 |
| --- | --- |
| 用户界面里填的值 | 让用户截图或口述；记录页面与字段 |
| `.pieproj` 存档 | 用户提供工程路径，只读取需要的字段 |
| 生成代码 | `pieblock-cli codegen <工程>` 的 stdout（规范输出） |
| 用户实际导出的 `main.c` | 可选：让用户从「生成代码」页导出，用来确认与 CLI 输出是否一致 |

工程有 error 时 `codegen` 会拒绝（退出 2）：先按 `validate` 的 issues 收敛参数问题，
或让用户补全工程后再对照。

### 2. 一致性检查

1. `pieblock-cli validate <工程>` → JSON；0 error 才能继续；
2. 用 `codegen` 生成规范 C；
3. 如果用户导出的 `main.c` 与 CLI 输出不一致：先怀疑版本不同步、导出后被手改、或构建缓存，
   而不是生成器 bug；
4. 按 `references/parameter-to-code.md` 的锚点逐字段对照参数与代码。

### 3. 对照参数与代码

对每个用户关心的字段做一行记录（表格形式给用户看）：

```text
参数（.pieproj 路径） | 界面值 | 生成代码落点 | 代码里的值 | 一致？
remote.channel         | 36     | uint8_t Channal = 36; | 36 | 是
chassis.normal_speed   | 6000   | uint16_t maxSpeed = 6000; | 6000 | 是
```

生成器会给模式动作表达式写定位注释 `/*@expr:modes.N.actions.M.expression*/`，
这是最可靠的对照锚点。完整锚点表见 `references/parameter-to-code.md`。

### 4. 判定

| 现象 | 结论 | 下一步 |
| --- | --- | --- |
| 界面值 ≠ 存档 | 保存/GUI 问题 | 让用户重新填写并保存；记录版本与复现步骤 |
| 存档 ≠ CLI 生成代码 | 生成器缺陷候选 | 收集证据，按第 6 步上报 |
| CLI 输出 ≠ 用户导出的 main.c | 版本不同步 / 导出被改 / 构建缓存 | 先统一版本、重新导出 |
| 参数与代码一致但行为不符 | 预期语义、硬件、接线、烧录或操作问题 | 查项目格式文档/固件约束/编译烧录指南/playbook |
| 编译失败 | 工具链或环境问题 | 收集完整 build log 与版本；不手改 C |
| 烧录失败 | HID/时序/驱动问题 | 指向编译烧录指南与 udev/pitfall 文档 |

### 5. 配置修正（如果是参数问题）

用 `pieblock-cli propose` 提交修正：复制工程 → 改临时候选 → `validate` + `codegen` →
`propose` → 用户在应用里确认。规则与 `pieblock-config` Skill 相同。

### 6. 疑似软件缺陷：整理证据，发飞书「机械培训群」

按 `references/bug-report-template.md` 整理成一段可直接粘贴的消息，让学生发到
飞书 **「机械培训群」**。**学生不需要自己开 GitHub Issue**；维护者会据此复现、排期，
必要时由维护者转成 Issue。公开讨论也方便其他人搜索同样的现象。

群消息先给结论（版本、现象、期望 vs 实际、参数对照结论，几行即可）；完整证据（`validate` JSON、
生成代码片段与行号、按 tag 的源码链接、最小工程）直接发在群里。`.pieproj` 只是普通参数，
**不需要脱敏，可以直接发**；截图/日志里如果带本机路径、用户名或无关窗口，自己看一眼再发即可。
**不要用飞书私聊**（组织限制也不允许）：所有线索留在群里，问题解决后把结论补在同一话题下，
方便其他人搜索和复用。

## 允许的源码阅读

- **Gitee 镜像（国内访问稳定，优先）**：<https://gitee.com/louqingjie/pie-block>（按 tag 阅读，如 `v1.8.0`）；
- GitHub 备用：<https://github.com/louqingjie/PIE-Block>（与 Gitee 同 tag 同内容）；
- raw 文件示例（Gitee）：`https://gitee.com/louqingjie/pie-block/raw/v1.8.0/packages/pieblock_core/lib/src/code_generator.dart`；
  GitHub 备用：`https://raw.githubusercontent.com/louqingjie/PIE-Block/v1.8.0/packages/pieblock_core/lib/src/code_generator.dart`；
- 生成器入口（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/code_generator.dart`；
- 表达式（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/expression.dart`；
- 字段模型与校验（按 tag 读 GitHub）：`packages/pieblock_core/lib/src/models.dart`、`validator.dart`；
- 文档（`pieblock-config` Skill 内）：`../pieblock-config/assets/docs/Flutter项目文件格式.md`、`../pieblock-config/assets/docs/Flutter编译与烧录指南.md`、
  `../pieblock-config/assets/docs/STC32G固件约束.md`；playbook 按 tag 读 GitHub `docs/playbook/`。

镜像与 GitHub 版本不一致时，以应用 `describe.release` 对应的 tag 为准，不要混用版本；Gitee raw 路径与
GitHub 相同，只换域名。**不要臆造不存在的仓库地址。**

## 拒绝话术

- 「你直接改 main.c 修一下」→ 说明生成产物会被覆盖，只能改参数；给 propose 流程。
- 「帮我编译/烧录验证」→ 编译烧录只在 PIE-Block 桌面版里做；可以帮用户把验证步骤和证据准备好。
- 「网上找个固件刷进去」→ 不允许；固件必须由 PIE-Block 从参数生成。
- 「你改一下源码不就好了」→ 源码只读；确认是缺陷就整理证据发到飞书「机械培训群」，
  不给用户本地补丁版。

## 参考

- 参数↔代码锚点：`references/parameter-to-code.md`
- Bug 报告模板：`references/bug-report-template.md`
- CLI 指南：按 tag 读 GitHub `docs/guides/PIE-Block命令行工具.md`
- 配置 Skill：`../pieblock-config/SKILL.md`（修改参数）
