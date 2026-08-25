# 代码生成器 CLI 与 MCP 接入指南（旧版归档）

> 本文仅记录 Godot 旧版接口。Flutter 格式 12 首版不提供 CLI/MCP，且这些接口不能读取新版 `.pieproj`；请勿用于新项目。

把 Pie-Block 图形化代码生成器做成**命令行工具**（Godot headless CLI），再包一层
**MCP Server**，让任何 AI Agent（Claude、GitHub Copilot、opencode 等）都能直接
调用同一套代码生成逻辑，生成步兵 / 工程 / 调试机器人固件，或生成 P33 蜂鸣器音乐固件。

**零逻辑重复**：CLI 直接复用 `scripts/codegen/*.gd` 和 `scripts/static_checker.gd`，
不重写任何生成规则。改 GUI 的生成器，CLI / MCP 自动跟着变。

```
┌─────────────┐    JSON-RPC     ┌────────────────────┐   subprocess   ┌────────────────────┐
│  MCP 客户端  │ <────────────>  │  tools/pieblock_   │ ─────────────> │  godot --headless  │
│  (Agent)     │  (stdio)        │  mcp_server.py     │   (每次调用)    │  scripts/          │
└─────────────┘                 └────────────────────┘                 │  cli_codegen.gd    │
                                                                        └────────────────────┘
                                                                                 │ 复用
                                                                        ┌────────▼────────┐
                                                                        │ codegen_*.gd    │
                                                                        │ static_checker  │
                                                                        └─────────────────┘
```

## 一、命令行 CLI

### 环境要求

- Godot 4.x（本项目用 4.7）在 PATH 中，或设置环境变量 `PIEBLOCK_GODOT` 指向
  可执行文件
- 无需打开 GUI，全 headless 运行

### 命令

```powershell
# 生成代码（配置 JSON -> stdout 输出 JSON，含 code 字段）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- generate --kind infantry --config my_config.json

# 生成代码并写入文件（stdout 只输出简短结果）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- generate --kind infantry --config my_config.json --out main.c

# 从 .pieproj 项目文件生成（复用项目里保存的配置）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- generate --project "调试项目.pieproj"

# 只跑静态检查，不生成代码
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- check --kind engineer --config eng_config.json

# 编译为 hex 固件（配置 JSON -> 生成 -> Keil C251 编译）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- build --kind infantry --config my_config.json

# 编译已有的 C 代码文件
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- build --kind infantry --code main.c

# 从 .pieproj 编译（优先用项目里已保存的代码）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- build --project "工程项目.pieproj"

# 输出配置 JSON Schema（字段定义）
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- schema --kind infantry

# 列出所有项目类型
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- profiles

# 帮助
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- help
```

> 必须带 `--no-header`，否则 Godot 启动横幅会混进 stdout，干扰 JSON 解析。
> 横幅（`Initialize godot-rust ...`）在第一行，真正的 JSON 从第一个 `{` 开始。

### 编译（build）说明

`build` 复用 `scripts/toolchain.gd` 的 `Toolchain.build_project()`。默认使用随
Windows 程序内嵌的 SDCC C251，首次使用时离线部署到 `user://`，然后写入
`main.c`、编译并校验 HEX/MAP 布局。

需要兼容验证时可加 `--compiler keil`。Keil 模式必须指定外部 Keil C251 安装
目录；headless 下没有图形引导，需在运行前指定路径，二选一：
>
> 1. 环境变量：`$env:PIEBLOCK_KEIL="C:\Keil_v5"`
> 2. 配置文件：往 `user://keil_settings.json` 写 `{"path": "C:\\Keil_v5"}`
>    （GUI 编译时也会引导填写同一文件）

- `--compiler sdcc|keil`，默认 `sdcc`
- 编译通常 10~60 秒
- 产物 hex 路径见返回 JSON 的 `hex` 字段
- **云端编译（可选）**：`build` 增加 `--remote <编译服务地址>`（如
  `http://127.0.0.1:8000`），则本机**不装 Keil**，改为把工程打包上传到
  `keil_server` 编译服务，服务器端 Keil C251 编译后返回 hex。可用
  `PIEBLOCK_PYTHON` 指定 python 解释器（建议指向项目 `.venv`）。
  `--remote` 始终表示服务器端 Keil，与本地 `--compiler` 和 GUI 持久化选择无关。
  服务搭建见 `keil_server/README.md`
- 已修复的编译漏洞：
  - `build` 曾用 Keil `-b`（跳过重编译，连续编译不同配置会返回陈旧 hex），
    已改用 `-r`（rebuild）强制重编译
  - `debug` 模式曾因未定义 `Channal` 变量（nrf24l01.c 依赖）而链接失败，已修复
  - 工程 `joint_count` 越界曾产生缺失数组声明的坏代码，已钳位并加检查器校验

### 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 参数错误 |
| 2 | 生成/编译失败 |
| 3 | IO 错误 |

### 输出格式

`generate`（无 `--out`）：

```json
{
  "ok": true,
  "kind": "infantry",
  "code": "// 步兵机器人操作代码...",
  "has_error": false,
  "issues": []
}
```

`check`：

```json
{
  "ok": true,
  "kind": "engineer",
  "issues": [ {"type": "Error", "msg": "..."} ],
  "error_count": 0,
  "warn_count": 0
}
```

> `has_error` = 配置存在 Error 级问题。**代码仍会生成**（供参考），
> 但真机烧录前必须清零。

### 音乐模式配置

音乐模式只接受项目中已经保存的 MIDI 解析结果，不读取 `source_name` 对应的原始文件。
Windows 桌面端通过图形界面导入 MIDI、选择轨道并保存后，可直接使用：

```powershell
godot --headless --no-header --path . --script scripts/cli_codegen.gd -- generate `
  --project "音乐项目.pieproj" --out main.c

godot --headless --no-header --path . --script scripts/cli_codegen.gd -- check `
  --kind music --config music.json
```

`music.json` 的结构为：

```json
{
  "music": {
    "source_name": "旋律.mid",
    "polyphonic": true,
    "track_index": 0,
    "track_indices": [0, 1],
    "track_name": "主旋律",
    "track_names": ["主旋律", "和弦"],
    "track_count": 2,
    "duration_ms": 1200,
    "segments": [
      {"notes": [64, 60], "duration_ms": 500},
      {"notes": [], "duration_ms": 100},
      {"notes": [64], "duration_ms": 600}
    ]
  }
}
```

`track_indices` 是选中的 MIDI 轨道索引；`polyphonic` 默认关闭，开启后最多保留四个最高音符，并以每声部 1us 的最短时间片轮换实现伪复音。`notes` 按音高降序排列，空数组表示休止；最多 8192 个片段，最长 20 分钟。
休止不会调用频率 0，代码生成器会将 `Ms_Delay` 长参数拆成多个 16 位延时。

## 二、MCP Server

### 安装依赖

```powershell
# 在项目的 Python 虚拟环境里安装 MCP 库
<项目根>/.venv/Scripts/python.exe -m pip install -r tools/requirements.txt
```

### 手动测试

```powershell
<项目根>/.venv/Scripts/python.exe tools/test_mcp_server.py
```

### 接入 Agent

把下面配置加进你的 MCP 客户端。把 `<项目根>` 换成你本机实际的项目根路径
（例如 `c:/Users/你的用户名/pie-block`），`cwd` 必须是项目根。

**Claude Desktop / Claude Code（`claude_desktop_config.json`）**：

```json
{
  "mcpServers": {
    "pie-block": {
      "command": "<项目根>/.venv/Scripts/python.exe",
      "args": ["tools/pieblock_mcp_server.py"],
      "cwd": "<项目根>"
    }
  }
}
```

**VS Code（`.vscode/mcp.json`）**：

```json
{
  "servers": {
    "pie-block": {
      "type": "stdio",
      "command": "<项目根>/.venv/Scripts/python.exe",
      "args": ["tools/pieblock_mcp_server.py"],
      "cwd": "<项目根>",
      "env": {
        "PIEBLOCK_CHANNEL": "36"
      }
    }
  }
}
```

> `env` 里的 `PIEBLOCK_CHANNEL` 是**默认遥控器通道号**（0-125）。设置了之后，
> 调用工具时如果 config 里 `channel` 为空或缺失，会自动填入该值。
> **优先级：工具显式 `channel` 参数 > config 里的 channel > `PIEBLOCK_CHANNEL`。**

### 提供的工具

| 工具 | 作用 |
| --- | --- |
| `list_profiles()` | 列出全部项目类型及用途 |
| `get_schema(kind)` | 获取某类型的配置 JSON Schema（字段/默认值/可选值） |
| `generate_code(kind, config, out_path?, channel?)` | 生成 main.c + 静态检查 |
| `check_config(kind, config, channel?)` | 只跑静态检查 |
| `generate_from_project(project_path, out_path?)` | 从 `.pieproj` 生成 |
| `build_code(kind, config, channel?)` | 生成代码并编译为 hex 固件（本地默认 SDCC） |
| `build_project(project_path)` | 从 `.pieproj` 编译（优先用已保存代码） |

`config` 是 **JSON 字符串**（不是对象）。`engineer` 直接接收扁平工程配置，
示例见 `tools/test_engineer_config.json`。

> `channel` 是**可选参数**（0-125）：传了就直接用它，不传则回落到 config 里的
> `channel` 字段，再没有才用环境变量 `PIEBLOCK_CHANNEL`。三种方式都不必在每次
> 调用时重复写完整配置。

> 编译工具 `build_code` / `build_project` 同步阻塞，通常 10~60 秒。Agent 应在
> 确认 `check_config` 无 Error 后再调用编译。

### 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PIEBLOCK_GODOT` | PATH 里的 `godot` | Godot 可执行文件 |
| `PIEBLOCK_ROOT` | server 文件上级×2 | 项目根目录 |
| `PIEBLOCK_CHANNEL` | 空（不填） | 默认遥控器通道号 0-125；config 里 channel 为空/缺失时自动填入 |
| `PIEBLOCK_KEIL_SERVER_URL` | 空（本地编译） | 设置后 `build_code` / `build_project` 改为**云端编译**（如 `http://127.0.0.1:8000`），本机无需装 Keil |
| `PIEBLOCK_KEIL_API_KEY` | 空 | 云端编译服务器的 API Key（服务器启用鉴权时必填） |

> 云端编译：设了 `PIEBLOCK_KEIL_SERVER_URL` 后，`build_code` / `build_project`
> 会把工程打包上传到该地址的 `keil_server` 编译服务，服务器端用 Keil C251 编译
> 并返回 hex（生成 main.c 仍在本机）。服务搭建见 `keil_server/README.md`。
> 不设置则保持本地编译，行为不变。

## 三、配置结构速查

每种 kind 的完整字段定义见 `docs/schemas/*.schema.json`（由 CLI `schema` 命令
生成，与代码保持同步）。核心字段：

### infantry（步兵）

| 字段 | 说明 | 默认 |
| --- | --- | --- |
| `channel` | NRF24L01 通道号 0-125 | "36" |
| `l1_io`…`r2_io` | 底盘四轮 IO（"通信脚 方向脚"，如 "P74 P24"；P64/P66 不可选） | P74-P77 |
| `booster_io` | 拨弹电机 IO（P64/P66 不可选） | "P60" |
| `yaw_drive` / `pitch_drive` | 云台驱动类型（舵机/电机） | 舵机 |
| `yaw_io` / `pitch_io` | 云台 IO（扩展板 P60-P77 或主控板 MP74/MP03） | |
| `pwm_group_init` | PWMA 固定 50Hz；PWMB 固定 10000Hz | `{"PWMA":"50Hz","PWMB":"10000Hz"}` |
| `io_role` | 各引脚角色：舵机/摩擦轮/抖动电机/平滑电机 | 按功能自动确定 |
| `feed_mode` | 拨弹模式：`目视闭环`=按住持续拨弹松开即停（不阻塞）；`阻塞开环`=按一下拨弹固定时长（阻塞主循环） | 阻塞开环 |
| `trigger_key` / `booster_key` | 扳机键 / 摩擦轮开关键 | |

### engineer（工程）

```json
{
  "channel": "36",
  "l1_io": "P74 P24", "...": "...",
  "pwm_group_init": { "PWMA": "50Hz", "PWMB": "10000Hz" },
  "io_role": { "P60": "舵机", "P62": "平滑电机", "P64": "抖动电机", "...": "..." },
  "mode_count": 4,
  "switch_strategy": "单击切换",
  "mode_switch_key": "E",
  "mode_keys": ["A", "B", "C", "D"],
  "modes": [
    {"rows": [{"key": "LX", "dir": "正", "mode": "速度", "param": "3000", "io": "P62"}]},
    {"rows": []},
    {"rows": []},
    {"rows": []}
  ]
}
```

### debug（调试）

```json
{
  "debug_rows": [
    {"pin": "P60", "drive_type": "舵机", "dir": 1, "value": 0, "enabled": true}
  ]
}
```

## 四、硬件红线（Agent 必须遵守）

来自 `docs/STC32G固件约束.md` 与 `docs/RM电控指南.md`，违反会烧坏机构或让车失控：

1. **只烧录主控板**，绝不向机械扩展板烧录程序
2. **扩展板 IO（P60/P62/P64/P66/P74/P75/P76/P77）只能通过
   `ExpansionBoradControl` 控制，禁止用 `PWM_*` 函数**，且使用前必须初始化
3. 步兵上 **P64/P66 固定用于两个摩擦轮**，不可改作轮电机或拨弹电机
4. 主控板 **MP74 / MP03 只能驱动舵机**，且与扩展板 P74 不是同一个 IO
5. 舵机角度都是「相对中位的偏移角」，区间 **[-90, +90]**
6. 工程模式切换键不能与模式内动作键冲突，模式选择键也不能重复（静态检查会报）
7. PWM 频率按 PWMA/PWMB 分组共享；步兵 PWMA 固定 50Hz、PWMB 固定 10000Hz，工程两组均可选择 50Hz 或 10000Hz
8. 电机/舵机角色与组频率不匹配时只产生 Warn；步兵 PWMA 输入 10000Hz 或 PWMB 输入 50Hz 属于 Error，CLI `generate` 不会生成该配置的代码

## 五、常见问题

- **"找不到 godot"**：装 Godot 4.x 加入 PATH，或设 `PIEBLOCK_GODOT`。
- **stdout 里第一个 `{` 之前有横幅**：属正常，解析时跳过即可（server 已处理）。
- **旧 `.pieproj` 无法打开**：格式 11 起不再自动迁移旧项目；请新建项目后重新配置。
