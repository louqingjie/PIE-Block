# 命令行工具（CLI）

`pieblock-cli` 是 PIE-Block 的只读命令行入口，给脚本和 AI Agent 用：

- 和桌面端共用同一套 `ProjectValidator` 与 `CodeGenerator`，校验结论、生成的 C 代码与
  GUI 完全一致；
- 只读：不改写 `.pieproj`，不编译、不烧录（这两个动作代价是硬件，只在桌面 GUI 里提供）；
- 随安装包附带独立可执行文件，用户机器不需要装 Flutter/Dart SDK。

## 可执行文件在哪

| 发行方式 | 路径 |
| --- | --- |
| Windows 安装版 | `<安装目录>\cli\pieblock-cli.exe`（默认 `C:\Program Files\PIE-Block\cli\`） |
| Windows 便携版 | 解压目录 `cli\pieblock-cli.exe` |
| Linux 包 | `bundle/cli/pieblock-cli` |
| 开发期（仓库内） | `dart run packages/pieblock_core/bin/pieblock.dart` |

Agent 或脚本也可以设置 `PIEBLOCK_CLI` 指向可执行文件，不依赖安装位置。

## PATH：免安装版会自动处理

Windows 免安装版（zip）第一次从解压目录启动时，应用会把 `<解压目录>\cli` 写进
**当前用户**的 PATH（`HKCU\Environment\Path`）：

- 不需要管理员权限，只影响当前 Windows 账户；
- 写入后**已经打开的终端不会更新**，新开一个终端 `pieblock-cli` 才可用；
- 写入成功会提示一次；应用被移动到新目录、或新版本解压到别处后，下次启动会自动
  删掉自己写过的旧条目、再写入当前目录；
- **同一个目录只加一次**：如果你从 PATH 里手动删掉了它，应用不会再偷偷加回来；
  想恢复时删除 `%APPDATA%\com.wpie\PIE-Block\cli-path.json` 后重启应用即可；
- 便携单文件版（解压到 `%LOCALAPPDATA%\PIE-Block\portable\...`）和开发构建
  （`build\windows\...`）不写 PATH——前者每次解压到带哈希的新目录，写进去只会变成垃圾；
- 写入记录在 `%APPDATA%\com.wpie\PIE-Block\cli-path.json`；直接删除应用目录不会
  清理 PATH，需要时用「系统属性 → 高级 → 环境变量」手动删掉那一条。

Linux 发行包解压即用，不会改 `~/.bashrc`；需要全局命令时自行建软链接。

## 命令

```powershell
pieblock-cli describe                               # 输出机器可读的命令契约（JSON）
pieblock-cli validate  <工程.pieproj>              # 校验，stdout 输出 JSON
pieblock-cli codegen   <工程.pieproj> [--out main.c] # 生成 main.c，stdout 输出纯 C 源码
pieblock-cli --help
```

### validate

无论有没有问题都会输出 JSON：

```json
{
  "ok": true,
  "valid": false,
  "project": { "kind": "infantry", "format": 23, "sourceFormat": 23 },
  "counts": { "errors": 1, "warnings": 0 },
  "issues": [
    {
      "severity": "error",
      "kind": "invalid",
      "fieldPath": "remote.channel",
      "message": "遥控器通道 999 超出 0–125",
      "stepId": "remote"
    }
  ]
}
```

- `project.format` 是**当前程序**支持的工程格式版本，`project.sourceFormat` 是文件里记录的版本；
- 有 `error` 级问题时退出码为 2，但 **stdout 里仍然有完整 JSON**——调用方要先读 stdout，
  再决定怎么处理非零退出码。

### codegen

- 默认把源码写到 stdout，摘要写到 stderr；
- `--out <file>` 直接写文件（父目录不存在会自动创建），此时 stdout 为空；
- 配置存在 `error` 级问题时拒绝生成，退出码 2，错误清单在 stderr（与 GUI 行为一致）。

## 输出约定

- **stdout 只放机器可读数据**：`validate`/`describe` 是 JSON，`codegen` 是纯 C 源码。
- **stderr 只放人类可读的进度与错误**：成功时也会有摘要行，不要把「stderr 非空」当成失败。
- 输出为 UTF-8，含中文；Windows 下用 `chcp 65001` 或按 UTF-8 读取。

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 参数错误（未知命令、缺少路径、未知参数） |
| 2 | 校验失败（存在 error 级问题；stdout 仍有 JSON） |
| 3 | IO 或格式错误（文件不存在、JSON 非法、字段结构错误、版本不兼容） |
| 4 | 代码生成失败 |
| 5 | 内部错误（兜底；设置 `PIEBLOCK_DEBUG=1` 可查看调用栈） |

## 示例

PowerShell：

```powershell
$cli = "$env:ProgramFiles\PIE-Block\cli\pieblock-cli.exe"
$result = & $cli validate .\麦轮工程.pieproj 2>$null | ConvertFrom-Json
if (-not $result.valid) { $result.issues | Where-Object severity -eq 'error' }

& $cli codegen .\麦轮工程.pieproj --out .\build\main.c
```

bash：

```bash
pieblock-cli validate robot.pieproj > result.json 2> progress.log || true
pieblock-cli codegen robot.pieproj --out main.c
```

## 给 Agent / Skill 的接入建议

1. 先执行一次 `pieblock-cli describe`，按其中的契约调用，不要在提示词里硬编码命令细节；
2. 工程文件路径以用户给出的为准；没有给出时只在当前目录找唯一的 `*.pieproj`，有多个就询问；
3. 先 `validate` 再 `codegen`；`codegen` 失败时把 stderr 的错误清单转述给用户；
4. 不要直接手改 `.pieproj`——CLI 目前不提供写入命令，手工改 JSON 会绕过字段校验；
5. 不要尝试让 CLI 编译或烧录，它不提供这两个动作。

## 已知限制

- 只读，没有写入命令；需要改配置时请在 GUI 里操作或让用户确认改动；
- 读取的是磁盘上的文件：GUI 有 500ms 防抖自动保存，正在编辑时可能读到稍旧的版本；
- 不支持的工程版本（过旧或由更新版本创建）会以退出码 3 拒绝，并在 stderr 给出升级提示；
- 开发期用 `dart run` 调用时每次启动约 2–3 秒；发布包里的独立可执行文件约 70 ms。
