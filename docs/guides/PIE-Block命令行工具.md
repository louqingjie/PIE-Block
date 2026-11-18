# 命令行工具（CLI）

`pieblock-cli` 是 PIE-Block 的命令行入口，给脚本和 AI Agent 用：

- 和桌面端共用同一套 `ProjectValidator` 与 `CodeGenerator`，校验结论、生成的 C 代码与
  GUI 完全一致；
- **不直接改写工程**：`propose` 只生成 `<工程>.proposed` 提案文件，由用户在 PIE-Block
  里确认后由应用写入（应用是工程文件的唯一写者）；
- 不编译、不烧录（这两个动作代价是硬件，只在桌面 GUI 里提供）；
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
pieblock-cli propose   <工程.pieproj> --config <候选.pieproj> [--force] # 生成改动提案
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

### propose

把改动作为**提案**交给用户确认，而不是直接改工程：

```powershell
# 1. 复制工程，在副本上修改要变的字段（保持完整 .pieproj JSON）
Copy-Item .\robot.pieproj .\robot.candidate.pieproj
# ... 编辑 robot.candidate.pieproj ...

# 2. 生成提案
pieblock-cli propose .\robot.pieproj --config .\robot.candidate.pieproj
```

- 成功后写出 `.\robot.pieproj.proposed`，stdout 输出：

```json
{"ok":true,"proposal":"…\\robot.pieproj.proposed","changed":1,
 "paths":["chassis.normal_speed"],"baseSha256":"…","createdAt":"…"}
```

- **不会修改 `robot.pieproj`**；用户在 PIE-Block 里打开该工程时会看到顶部横幅，
  可查看逐字段差异、应用或丢弃。应用后工程才写入，且支持一步撤销；
- 候选必须是完整的 `.pieproj`：工程类型必须一致，且每个写出的字段值必须能被项目模型
  原样读回（拼错的枚举、未知字段会被拒绝，不会静默变成默认值）；
- 候选**不得引入新的 error 级校验问题**；工程本身还没配置完时，已有错误允许保留——
  AI 不需要先把无关字段填完。应用里会提示「工程仍有 N 个错误」；
- 已有待确认提案时默认拒绝，退出码 6；确认覆盖时加 `--force`；
- 提案带 `baseSha256`：应用侧发现工程在提案生成后又被保存过，会提示「基于旧版本」；
- 应用/丢弃后，应用会写 `robot.pieproj.proposed.result`（`{"status":"applied"|"discarded"}`），
  方便 Agent 侧做后续判断（当前 CLI 不读取它）。

## 输出约定

- **stdout 只放机器可读数据**：`validate`/`propose`/`describe` 是 JSON，`codegen` 是纯 C 源码。
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
| 6 | 已有待确认的提案（未加 `--force`） |

## 示例

PowerShell：

```powershell
$cli = "$env:ProgramFiles\PIE-Block\cli\pieblock-cli.exe"
$result = & $cli validate .\麦轮工程.pieproj 2>$null | ConvertFrom-Json
if (-not $result.valid) { $result.issues | Where-Object severity -eq 'error' }

& $cli codegen .\麦轮工程.pieproj --out .\build\main.c

# 提交改动提案：先改副本，再 propose，最后由用户在应用里确认
& $cli propose .\麦轮工程.pieproj --config .\麦轮工程.candidate.pieproj
```

bash：

```bash
pieblock-cli validate robot.pieproj > result.json 2> progress.log || true
pieblock-cli codegen robot.pieproj --out main.c
pieblock-cli propose robot.pieproj --config robot.candidate.pieproj
```

## 给 Agent / Skill 的接入建议

1. 先执行一次 `pieblock-cli describe`，按其中的契约调用，不要在提示词里硬编码命令细节；
2. 工程文件路径以用户给出的为准；没有给出时只在当前目录找唯一的 `*.pieproj`，有多个就询问；
3. 先 `validate` 再 `codegen`；`codegen` 失败时把 stderr 的错误清单转述给用户；
4. **改配置一律走 `propose`**：复制工程 → 在副本上改 → `propose --config`；不要直接改
   `.pieproj`，也不要指望 CLI 会写工程——写入由用户在应用里确认。工程还没配置完也能
   propose，只要不新增校验错误；
5. `propose` 返回 6 时说明用户还没处理上一份提案：不要自动加 `--force`，先问用户；
6. 不要尝试让 CLI 编译或烧录，它不提供这两个动作。

## 已知限制

- CLI 不直接写工程：提案必须由用户在 PIE-Block 里确认后才会应用（应用需处于打开状态）；
- 同一工程同一时间只保留一份待确认提案，新提案需要 `--force` 覆盖；
- 读取的是磁盘上的文件：GUI 有 500ms 防抖自动保存，正在编辑时可能读到稍旧的版本；
  提案会记录基线哈希，应用侧会提示「基于旧版本」；
- 提案只在桌面文件路径上生效；Web 与 Android（content URI）不支持；
- 不支持的工程版本（过旧或由更新版本创建）会以退出码 3 拒绝，并在 stderr 给出升级提示；
- 开发期用 `dart run` 调用时每次启动约 2–3 秒；发布包里的独立可执行文件约 70 ms。
