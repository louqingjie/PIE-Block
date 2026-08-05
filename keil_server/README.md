# keil_server — 云端 Keil C251 编译服务

把「上传 Keil 工程 zip → 服务器用 Keil C251 原生编译 → 下载 HEX」做成一个
HTTP 编译服务。先在本机搭建验证，之后可原样部署到云服务器。

服务端**不做**代码生成、**不做**烧录，只负责一件事：把客户端给的工程 zip
用服务器上安装的 Keil C251 编译成 hex。核心逻辑复刻自项目内
`scripts/toolchain.gd` 已验证的编译经验。

## 接口（异步任务模型）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 服务健康 + Keil 安装探测（路径、许可证状态） |
| POST | `/compile` | multipart 上传 `file`=zip，可选 `timeout`（5~600 秒）。返回 `task_id` |
| GET | `/tasks` | 任务列表（`limit` 参数） |
| GET | `/tasks/{id}` | 任务状态：`queued → building → success \| failed` |
| GET | `/tasks/{id}/log` | 完整编译日志（text/plain） |
| GET | `/tasks/{id}/hex` | 下载 hex 固件（成功时） |
| DELETE | `/tasks/{id}` | 清理任务 |

典型流程：

```text
POST /compile (zip) ──> {"task_id": "a1b2c3"}
GET  /tasks/a1b2c3    ──> {"status": "building"}   （轮询直到 success/failed）
GET  /tasks/a1b2c3/hex ──> 下载 .hex
GET  /tasks/a1b2c3/log ──> 完整编译日志
DELETE /tasks/a1b2c3   ──> 清理
```

任务成功时 `summary` 给出 Program Size（`code`/`xdata`/`data`/`const`）。
编译失败时 `error` 说明原因；许可证受限（`RESTRICTED VERSION` / `ERROR L250`）
会被单独识别并给出明确提示。

## 目录结构

```
keil_server/
├── config.py          配置（Keil 路径、并发、超时、大小限制、任务 TTL）
├── safe_unzip.py      安全解压（防 zip-slip 路径穿越 / zip bomb）
├── tools_ini.py       TOOLS.INI [C251] 段解析与修复
├── keil_detect.py     Keil 安装探测与校验（含精简工具链部署副本）
├── compiler.py        编译核心（uVision.com -r、日志解析、hex 定位）
├── task_manager.py    任务状态机 + 并发控制 + 持久化 + TTL 清理
├── server.py          FastAPI 入口（uvicorn）
├── make_fixture.py    生成自包含工程 zip 夹具（测试/演示用）
├── tests/             单元 + 集成 + API 端到端测试
└── data/              运行数据（gitignore）：任务目录、部署的工具链副本
```

## 本机搭建

### 1. 安装完整正版 Keil C251（生产形态，本机也建议这么做）

1. 到 keil.com 下载 **Keil C251** 安装包，双击全新安装到
   `C:\Keil_v5`（C251 与 MDK 同装一个根目录）。
2. 申请许可证：keil.com 注册后按机器 **License ID Code** 领取免费 C251 密钥。
   License ID Code 可在安装后的 `UV4.exe → License Management` 查看。
3. 许可证是**机器绑定**的，写入安装目录的 `TOOLS.INI` 的 `[C251]` 段 `LIC0=`。
   没有有效密钥时 Keil 退回 2KB 评估限制，编译会报 `RESTRICTED VERSION` /
   `ERROR L250`（本服务会识别并提示，不做任何破解/补丁）。

### 2. 安装依赖

```powershell
<项目根>\.venv\Scripts\python.exe -m pip install -r keil_server/requirements.txt
```

### 3. 启动

```powershell
# 从项目根
<项目根>\.venv\Scripts\python.exe -m uvicorn keil_server.server:app --host 0.0.0.0 --port 8000
```

Keil 路径解析优先级：
1. 环境变量 `KEIL_PATH`（推荐：装好完整版后指向 `C:\Keil_v5`）
2. 自动探测候选：`C:\Keil_v5`、`C:\Keil`、项目内 `stc32g/toolchain/Keil_noarm`

> 开发/冒烟：没装完整版时，服务会自动用项目内分发的精简工具链
> `Keil_noarm`（结构与完整版一致）。它会先被**部署副本**到
> `keil_server/data/keil`（可写目录）再使用，不会改动仓库里的原始文件。
> 注意精简版带的是开发机许可证，换机器编译会许可证受限。

### 4. 验证

```powershell
# 生成一个自包含工程 zip 夹具（需要 Godot，PIEBLOCK_GODOT 指向 godot）
$env:PIEBLOCK_GODOT="C:\...\Godot_v4.7...\godot.exe"
<项目根>\.venv\Scripts\python.exe -m keil_server.make_fixture --project infantry --out %TEMP%\infantry.zip

# 走一遍完整链路
curl http://127.0.0.1:8000/health
curl -F "file=@%TEMP%\infantry.zip" http://127.0.0.1:8000/compile
# ... 轮询 /tasks/{id} 直到 success，再下载 /tasks/{id}/hex
```

### 5. 跑测试

```powershell
$env:PIEBLOCK_GODOT="C:\...\godot.exe"   # 生成夹具需要
<项目根>\.venv\Scripts\python.exe -m pytest keil_server/tests -v
```

无 Keil / 无 Godot 的环境会**跳过**集成与 API 端到端测试（单元测试始终跑）。

## 云端部署

服务本身与平台无关（Windows / Linux 均可，Keil 是 Windows 程序，云服务器
需是 Windows 实例）。建议：

- Windows 云服务器上同样**原生全新安装正版 Keil C251 + 申请许可证**，
  设环境变量 `KEIL_PATH` 指向安装目录
- `pip install -r keil_server/requirements.txt`，用 uvicorn 常驻
  （systemd/NSSM 托管），前端加 Nginx 反向代理 + HTTPS
- 安全加固（按需）：
  - 上传/解压限制默认已开（`UPLOAD_MAX_SIZE` / `EXTRACT_MAX_SIZE` / `EXTRACT_MAX_FILES`）
  - 生产环境建议加 API Key 鉴权或部署在内网/VPN
  - `GET /tasks/{id}/log` 可能含源码路径，注意访问控制

## 配置（环境变量，全部可覆盖）

| 变量 | 默认 | 说明 |
|---|---|---|
| `KEIL_PATH` | （空） | Keil 根目录，最高优先级 |
| `KEIL_SERVER_DATA_DIR` | `keil_server/data` | 任务与工具链副本存储 |
| `KEIL_MAX_CONCURRENT` | `1` | 最大并发编译数（Keil 共享 TOOLS.INI，默认 1 最稳） |
| `KEIL_BUILD_TIMEOUT` | `120` | 单次编译超时（秒） |
| `KEIL_UPLOAD_MAX_SIZE` | 50MB | 上传 zip 上限 |
| `KEIL_EXTRACT_MAX_SIZE` | 300MB | 解压总量上限（防 zip bomb） |
| `KEIL_EXTRACT_MAX_FILES` | 2000 | 解压文件数上限 |
| `KEIL_EXTRACT_MAX_FILE_SIZE` | 50MB | 单文件解压上限 |
| `KEIL_TASK_TTL` | 3600 | 已完成任务保留时长（秒），到期自动清理 |
| `KEIL_SERVER_HOST` / `KEIL_SERVER_PORT` | `127.0.0.1` / `8000` | `python -m keil_server.server` 直接运行时的监听地址 |

## 输入 zip 约定

- **完整自包含工程**：zip 内需含 `.uvproj`（优先 `Project_Template.uvproj`）、
  `USER/`、`MDK/`、`Libraries/`（保持 uvproj 相对引用可解析）。
- 服务端解压后自动定位工程文件编译，不套模板、不生成代码。
- 编译成功判据：Keil 日志含 `0 Error(s)`（退出码不可靠）。

## 关键实现要点

- **`-r` rebuild**：用 `-b` 会跳过重编译，连续编译不同工程返回陈旧 hex
- **TOOLS.INI**：`[C251] PATH=` 必须反斜杠绝对路径；读写限定在 `[C251]`
  段内（`[ARM]` 段也有 `LIC0`，别误读误写）；按行编辑用 latin-1 保字节
- **超时树杀**：uVision.com 会拉起 UV4.exe，超时用 `taskkill /T /F` 整树终止
- **清理旧 hex**：编译前删掉 `MDK/Objects/*.hex`，防止失败时返回上次产物
- **隔离**：每任务独立目录；解压防 zip-slip / zip bomb；完成后按 TTL 清理
