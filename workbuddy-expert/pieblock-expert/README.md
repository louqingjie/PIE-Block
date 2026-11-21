# PIE-Block 助手（WorkBuddy 专家包）

把 PIE-Block 的两个 AI 规程（工程配置 / 生成代码排障）装进 WorkBuddy：一个「PIE-Block 助手」专家，
内置 `pieblock-config` 与 `pieblock-troubleshooting` 两个技能。

## 结构

```
pieblock-expert/
├── .codebuddy-plugin/plugin.json   # 专家配置（categoryId=02-Engineering）
├── avatars/expert.png              # 软件图标 512×512
├── agents/pieblock-assistant.md    # 人设、红线、工作流
├── skills/
│   ├── pieblock-config/            # SKILL.md + references + assets（示例/文档）
│   └── pieblock-troubleshooting/
└── README.md
```

## 安装（私有专家原型）

1. 在 WorkBuddy 安装官方 `expert-manager` 技能（聊天框里让它安装，要求 `git clone`）；
2. 让 WorkBuddy 用 `expert-manager` 校验并注册本目录（或按 `expert-manager` 的流程导入）；
3. 注册后在「专家中心 → 我的专家」里召唤「PIE-Block 助手」。

## 上架（公开市场）

把本目录打成 zip 提交到 <https://open.workbuddy.cn>，审核后学生可在专家市场直接召唤。
上架前需补齐头像/描述审核要求，并把 `plugin.json` 的 author、homepage、license 核对成最终值。

## 边界

两个技能都禁止 AI 直接修改 `main.c`、绕过代码生成器、编译/烧录固件；配置改动只能通过
`pieblock-cli propose` 提交，由用户在 PIE-Block 里确认。专家只是分发载体，不改变这条边界。
