# PIE-Block DSH Skills 插件

把 PIE-Block 的两个 Agent 规程（`pieblock-config` 配置 / `pieblock-troubleshooting` 排障）
作为 **DSH 全局 skill** 提供给所有会话。插件只装载 skill，没有运行时代码、不写用户目录。

## 安装

- DSH 侧边栏 **Plugins → Add plugin → 本地目录**，选择本目录；
- 或在会话里让 Agent 用 `plugin_manager` 的 `install_bundle` 安装本目录的绝对路径。

安装后开一个新会话（已有会话会在下一次目录刷新时追加技能目录），技能目录里应出现：

- `pieblock-config`
- `pieblock-troubleshooting`

## 卸载

Plugins 页移除本插件即可；skill 随 provider 注销消失，`~/.dsh/skills` 不会留下任何文件。

## 内容

```
skills/pieblock-config/
  SKILL.md
  references/            # 需求澄清、构型配方、候选构建流程
  assets/examples/       # omni3 / mecanum4 / arm2dof 示例工程
  assets/docs/           # 项目格式、固件约束、编译烧录指南
skills/pieblock-troubleshooting/
  SKILL.md
  references/            # 参数↔代码锚点、bug 报告模板
  assets/examples/
```

## 边界

两个 skill 都禁止 AI 直接修改 `main.c`、绕过代码生成器、编译/烧录固件；配置修改只能
通过 `pieblock-cli propose` 提交，由用户在 PIE-Block 里确认。插件只是分发载体，不会改变
这条边界。
