# PIE-Block AI 规程（DSH 插件）

把 PIE-Block 的两个 AI 规程装进 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)：

- `pieblock-config`：按自然语言配置工程参数（麦轮 / 全向轮底盘、二自由度机械臂、发射机构、模式与按键等）；
- `pieblock-troubleshooting`：对照界面参数、`.pieproj` 与生成代码排障，整理可复现的 bug 证据。

装一次，**所有 DSH 会话可见**，与工作目录、Agent 预设无关；不需要 PIE-Block 源码仓库。

npm 包页：<https://www.npmjs.com/package/pieblock-dsh-skills>

## 安装

DSH 里有两种方式：

1. **Plugins 页**：打开侧边栏 **Plugins → Add plugin**，输入包名 `pieblock-dsh-skills`；
2. **命令行**（如果 `dsh` 在 PATH）：

   ```bash
   dsh plugin --profile web add pieblock-dsh-skills
   ```

安装后开新会话，技能目录里会出现 `pieblock-config` 与 `pieblock-troubleshooting`。
技能自带的示例工程与文档在插件包的 `skills/*/assets/` 下，离线可用。

### 本地开发安装

```bash
dsh plugin --profile web add link:D:/path/to/pie-block/dsh-bundle/pieblock-dsh-skills
```

或在 Plugins 页 **Add plugin → 本地目录** 选择本目录。

## 卸载

Plugins 页移除本插件，或：

```bash
dsh plugin --profile web remove pieblock-dsh-skills
```

skill 随插件注销消失，`~/.dsh/skills` 不会留下任何文件。

## 内容

```
index.js                       # apply 时把两个 Skill 注册进 DSH skill 注册表
cordis.patch.yml               # 只插入一个 Host 插件行
skills/pieblock-config/        # SKILL.md + references + assets/examples + assets/docs
skills/pieblock-troubleshooting/
locale/{zh,en}.json            # 插件标题与说明
icon.svg
```

## 边界

两个 Skill 都禁止 AI 直接修改 `main.c`、绕过代码生成器、编译/烧录固件；配置修改只能通过
`pieblock-cli propose` 提交，由用户在 PIE-Block 里确认。插件只是分发载体，不改变这条边界。

## 兼容

面向 DSH 0.2.x（Web / Desktop）。插件只使用 `ctx.skills.register(...)` 与随包 Markdown，
不依赖其他插件包。
