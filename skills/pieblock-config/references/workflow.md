# 候选构建与自检流程

## 1. 找到 CLI 并读契约

```powershell
pieblock-cli describe
```

- PATH 里没有时：用环境变量 `PIEBLOCK_CLI`，或应用目录下的
  `cli/pieblock-cli.exe`（便携版/安装版）、`build\windows\x64\runner\Release\cli\pieblock-cli.exe`（开发构建）；
- `formatVersion` 应等于工程 `format_version`；若 `describe` 提供 `release`（旧版 CLI 可能没有），它应与安装包版本前缀一致。`version` 只是 CLI 工具版本，不要与应用版本比较。不一致时先让用户升级，再做配置。

契约要点：stdout 只放机器可读数据，stderr 是人类可读进度；退出码：

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 参数错误 |
| 2 | 校验失败 / 提案被拒 |
| 3 | IO 或格式错误 |
| 4 | 代码生成失败 |
| 5 | 内部错误 |
| 6 | 已有待确认提案（需 `--force`，但要先问用户） |

## 2. 构建候选（只在临时目录）

1. 取基线：用户当前 `.pieproj`（改现有工程）或示例/模板（新工程）。
2. 复制到临时目录，例如 `%TEMP%\pieblock-<时间戳>\candidate.pieproj`；
3. 只改 `config`：
   - 保持 `format_version`、`project_kind` 与目标工程一致；
   - 逐字段改，不要删除看不懂的字段（尤其是 `pwm.pin_roles`、`servo_mids`、`guide_progress`）；
   - 枚举写稳定英文值（`forward`/`reverse`、`motor`/`servo`/`friction`/`unused`、`cycle`/`direct` 等）；
   - 不确定的硬件值不要编：回到 `questionnaire.md` 问用户。
4. 记下你改了哪些路径（后面要向用户复述）。

> 不要用脚本「重新发明」生成器逻辑。这里改的只是工程 JSON，生成代码永远由 `codegen` 产出。

## 3. 自检门禁

```powershell
# 1) 校验：stdout 是 JSON
pieblock-cli validate <候选.pieproj>

# 2) 生成：必须成功，stdout 是纯 C 源码
pieblock-cli codegen <候选.pieproj>
```

判定：

- `validate` 退出 0 且 `valid: true` → 通过；
- 有 error：按 `issues[].fieldPath` / `message` 修候选，再重跑；
- 有 warning：向用户说明，不阻断（例如「拨弹电机在 50 Hz 组」）；
- `codegen` 非 0：按 stderr 定位；**不要提交生成不出代码的候选**。

## 4. 提交提案

```powershell
pieblock-cli propose <用户工程.pieproj> --config <候选.pieproj>
```

- 成功：stdout 返回 `{ok, proposal, changed, paths, baseSha256, createdAt}`；
- 把 `changed` / `paths` 翻译成用户能懂的变更清单；
- 退出 6：已有待确认提案。先问用户「旧提案要丢弃还是应用？」，用户确认后再决定是否 `--force`；
- 退出 2：候选被拒（类型不一致 / 新校验错误 / 往返核对失败 / 无差异），按 stderr 字段修候选；
- 退出 3：路径或 JSON 问题，检查候选文件是否完整。

## 5. 用户确认

告诉用户：

1. 在 PIE-Block 打开该工程；
2. 顶部横幅「AI 提交了改动提案」→「查看」看逐字段差异 →「应用」；
3. 应用后可用 Snackbar 的「撤销」回退一步；重要工程建议先手动备份 `.pieproj`。

不要替用户点「应用」，也不要让他跳过查看。

## 6. 应用之后

- 生成代码页：确认预览的 C 代码可用；需要时用「检查与试算」核对表达式；
- 编译、烧录：由用户在应用内完成（AI 不执行 SDCC/Keil/HID）；
- 台架：轮子悬空、低占空比起步、单轮点动确认方向、再整体验证；
- 行为仍不对 → 转 `pieblock-troubleshooting` Skill，按参数↔代码锚点对照。

## 7. 失败与回滚

| 情况 | 处理 |
| --- | --- |
| validate 报错 | 修候选重跑，不提交 |
| codegen 失败 | 修表达式/参数，不提交 |
| propose 2 | 看 stderr 字段路径；不要改用户工程来「绕过」 |
| propose 6 | 先问用户；不要自动 `--force` |
| 用户点了应用但结果不对 | 用应用内「撤销」回退一步；必要时用备份恢复 `.pieproj` |
| 用户中途改主意 | 让用户在应用里点「丢弃」，提案文件会被删掉 |

## 8. 临时文件

候选与生成日志放临时目录，结束后清理；不要往用户工程目录写候选、`.bak` 之外的任何文件。
