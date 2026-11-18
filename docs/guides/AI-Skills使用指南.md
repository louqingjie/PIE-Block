# AI Skills 使用指南

PIE-Block 提供两个 Agent Skill，把「AI 帮用户折腾工程」限制在安全、可回滚的路径上：

| Skill | 目录 | 用途 |
| --- | --- | --- |
| `pieblock-config` | [`skills/pieblock-config/`](../../skills/pieblock-config/SKILL.md) | 按自然语言需求设计/填写工程参数（麦轮、全向轮、机械臂、发射机构等） |
| `pieblock-troubleshooting` | [`skills/pieblock-troubleshooting/`](../../skills/pieblock-troubleshooting/SKILL.md) | 怀疑生成代码有问题时对照参数与 `main.c`、读源码、整理 bug 报告 |

两个 Skill 都只做「读 + 改参数 + 生成提案」；真正写入工程、生成代码、编译、烧录都由用户在
PIE-Block 里完成。

## 红线

1. **不直接修改 `main.c`**：生成代码只读，不提供可粘贴替换的补丁。
2. **不绕过代码生成器**：固件行为只能由 `.pieproj` 参数 + PIE-Block 生成器产生；不手写/拼装固件、
   不复刻生成器、不给「本地修过的生成器」。
3. **不编译、不烧录**：不运行 SDCC/Keil/HID/ISP，不产出 HEX/BIN，不教用户绕开应用的生成/烧录页。
4. **不直接写用户工程**：AI 只写临时目录里的候选 `.pieproj`，落盘通过 `pieblock-cli propose`，
   由用户在应用里确认；不得擅自 `--force` 覆盖待确认提案。
5. **不臆造硬件参数**：引脚、方向、通道、速度由用户确认，默认值必须标注假设。
6. **不承诺固件正确性**：应用、编译、烧录、测试、上场由用户负责。

## 怎么装

Skill 采用通用的 Agent Skills 格式（`SKILL.md` + YAML frontmatter），可被支持该格式的 Agent
直接加载；不支持 Skills 的工具，把 `SKILL.md` 正文贴进系统提示词/自定义指令即可。

常见做法：

1. 把 `skills/pieblock-config/` 或 `skills/pieblock-troubleshooting/` 整个目录复制到你所用
   Agent 的 skills 目录（例如 Claude Code 的个人 skills 目录 `~/.claude/skills/`；其他工具
   按各自文档放置）；
2. 或者把整个 `skills/` 目录放到项目里，让 Agent 从工程目录读取；
3. 确保 Agent 能访问 `pieblock-cli`（PATH、`PIEBLOCK_CLI`，或应用目录下的 `cli/`）。

> 本 Skill 不随安装包分发，也不是 MCP / 常驻服务；它只是给 AI 的规程文件。

## 典型对话

### 配置：帮我配置三轮全向底盘

用户：「帮我配一个三轮全向轮底盘，P74–P76 接三个电机。」

AI 按 `pieblock-config`：

1. 问清工程类型（必须是「工程」）、通道、模式数、速度、轮位与方向；
2. 从 `book/examples/omni3.pieproj` 生成候选，按用户硬件改通道/引脚/表达式；
3. `validate` + `codegen` 自检；
4. `propose`，告诉用户「改了哪些字段、哪些是默认假设」；
5. 用户在 PIE-Block 里查看差异 → 应用 → 生成代码 → 编译烧录 → 台架验证。

### 排障：代码里的速度和界面不一致

用户：「我填的普通速度 6000，生成的代码里是 4000。」

AI 按 `pieblock-troubleshooting`：

1. 确认版本一致；
2. 收集界面值、`.pieproj`、`codegen` 输出；
3. 按锚点表核对 `chassis.normal_speed` ↔ `uint16_t maxSpeed`；
4. 判断是存档没保存、版本不同步还是生成器缺陷；
5. 是参数问题 → 用 `propose` 修正；疑似缺陷 → 按模板整理 Issue。

## 为什么不直接让 AI 改代码

- `main.c` 是生成产物，下次生成会被覆盖，手改无法维护；
- AI 改坏的固件一旦上车，责任会落到软件作者头上；
- 参数——生成器——用户确认的链路才可回滚、可审计、可复现。

## 维护

- 生成器/格式升级后，复核 `skills/pieblock-troubleshooting/references/parameter-to-code.md`
  的锚点，以及 `skills/pieblock-config/references/config-recipes.md` 的公式与示例；
- `test/agent_skill_docs_test.dart` 会校验两个 Skill 的 frontmatter、红线关键词与本地链接；
- 教材第 5 章的构型能力矩阵变化时，同步更新配置 Skill 的能力矩阵。
