# AI Skill 安装提示词

技能是标准 Agent Skills 目录，主流 AI 工具（Claude Code / Codex / Cursor / Gemini CLI /
Antigravity / VS Code Copilot / Trae / CodeBuddy / WorkBuddy / DSH …）都支持按目录加载，
**Agent 自己知道该装到哪、怎么验证**。所以「统一办法」只有一句话：

## 复制这段发给 AI

```text
帮我安装 PIE-Block 的两个 Agent Skill：pieblock-config、pieblock-troubleshooting。
源用 npm 包 pieblock-dsh-skills，不需要 npm：下载
https://registry.npmmirror.com/pieblock-dsh-skills/latest 返回的 dist.tarball（国内镜像，
失败就换 https://registry.npmjs.org/pieblock-dsh-skills/latest），解压后 package/skills/ 就是。
装到你自己加载 skills 的目录，装完告诉我路径。
```

## 为什么够用

- Agent 清楚自己是什么工具、skills 目录在哪、怎么触发验证，不需要我们替它列路径；
- **不需要 npm / node，也不用 clone 仓库**：直接 HTTP 下载 tarball（Windows 自带 `tar` 解压），
  国内默认走 npmmirror 镜像，失败自动回退官方 registry；
- 技能源固定（`latest`），技能更新后这段提示词不用改；
- 包里的技能是自包含副本（带 `references/`、`assets/`），Agent 不会误拿仓库根的源码版
  `skills/`（那份没有 `assets/`）。

## 例外

- 只能 UI 导入的工具（Trae 技能页、WorkBuddy 专家包、DSH 插件页）：直接说「装成插件 / 专家包」，
  Agent 会给出操作步骤；
- 完全不支持 Skills 的工具：让它把 `SKILL.md` 正文并入项目规则（`AGENTS.md` 等）；
- 完全离线（机房断网）：先在有网的机器上下载 tarball、解压出两个技能目录，再拷过去；
  PIE-Block 目前不随安装包分发技能。

## 维护

- 新增工具不用改提示词，Agent 自己适配；
- 技能改动后要在 `dsh-bundle/pieblock-dsh-skills/` 发一次 npm 版本：提示词永远取 `latest`，
  不发版学生装到的就是旧技能；
- 关键来源与「提示词要短」由 `test/agent_skill_docs_test.dart` 锁定。
