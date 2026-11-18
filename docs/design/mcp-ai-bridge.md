# AI 接入（MCP）：契约、授权与边界

面向外部 AI Agent 的接入层，首版（P0）只做**桌面端本地服务 + 契约包**，不内嵌任何
Agent 运行时，也不改写任何第三方客户端的配置文件。

## 定位

PIE-Block 是**被调用方**：它把「读配置、校验、提改动、看代码」六个工具按
[MCP](https://modelcontextprotocol.io) 暴露到 `127.0.0.1`，CodeBuddy / Qoder /
DSH 等客户端作为调用方接进来。换客户端不需要改代码，改的是客户端的 MCP 配置。

三条硬边界：

1. **契约与 Agent 无关**。消息编解码、工具声明、补丁引擎全在 `packages/pieblock_mcp`，
   不依赖 Flutter，`dart test` 独立验收。
2. **写入口唯一**。AI 的改动最终落到 `AppController.updateConfig`，与界面手改共用
   校验、撤销与 500ms 防抖保存。
3. **授权集中在开关上**。不逐次弹确认卡片：打开「AI 接入」即表示信任该客户端，
   不信任时关掉开关或重置令牌即可切断。

## 分层

```text
CodeBuddy / Qoder / DSH ──POST /mcp + Bearer──▶ McpHttpServer（dart:io，仅桌面）
                                                    │
                                              McpServer（JSON-RPC 分发）
                                                    │
                                        McpToolRegistry（六个 pieblock_*）
                                                    │
                                    PatchEngine + McpFieldCatalog
                                                    │
                                        McpHost（宿主实现）
                                                    │
                                 AppController.updateConfig → Validator → .pieproj
```

Web 与 Android 不提供本地服务（浏览器无法监听端口），UI 上入口直接不出现。

## 传输与发现

- 只绑 `127.0.0.1`，端口传 0 由系统分配；路径固定 `/mcp`，其它路径 404。
- 鉴权：`Authorization: Bearer <token>`，也接受 `?token=`（部分客户端不支持自定义头）。
  token 每进程随机生成（24 字节 base64url）。
- 请求体上限 1 MiB，超限 413；通知类消息回 202 且不带 body。
- 发现文件写到应用数据目录的 `mcp-bridge.json`：

```json
{
  "schema": 1,
  "app": "pieblock",
  "path": "/mcp",
  "port": 51234,
  "endpoint": "http://127.0.0.1:51234/mcp",
  "token": "…",
  "pid": 12345,
  "startedAt": "2026-11-17T10:00:00.000"
}
```

服务停止时删除该文件。

端口与令牌另外存在应用数据目录的 `mcp-identity.json`（默认端口 `47173`，
token 首次启动随机生成），**退出不删**。因此重启 PIE-Block 后端点与令牌都不变，
客户端只需配置一次；只有主动点面板里的「重置令牌」或改端口才需要重新配置。
`mcp-bridge.json` 只是运行时发现文件，`mcp-identity.json` 才是本机身份。

## 工具

| 工具 | 语义 | 副作用 |
| --- | --- | --- |
| `pieblock_handshake` | 应用版本、协议版本、项目类型、revision、步骤列表 | 无 |
| `pieblock_get_context` | 指定步骤的字段清单：路径、中文名、当前值、范围、枚举 | 无 |
| `pieblock_validate` | 对当前或传入配置跑 `ProjectValidator` | 无 |
| `pieblock_propose_patch` | ops → `patchId` + diff + 改动后的 issues | 无（只有缓存） |
| `pieblock_apply_patch` | 提交 `patchId`，revision 未变时直接写入 | **写项目** |
| `pieblock_generate_code` | 分页返回 `main.c` 片段 | 无 |

编译与烧录**不暴露**：这两个动作出错代价是硬件，不值得为省几次点击开放。

## 补丁语义

```json
{"op": "set", "path": "chassis.normal_speed", "value": 4200}
{"op": "remove", "path": "modes[1].action_tables[0].rows[3]"}
```

- 路径是 `ProjectConfig.toJson()` 的结构，与 `ValidationIssue.fieldPath` 共用字段命名；
  数组用具体下标（`modes[1].actions[0]`），不接受 `[*]`。
- 只有 `McpFieldCatalog` 里登记且 `writable` 的字段能改；`id` 一律只读。
- `remove` 主要用于数组元素。标量字段请用 `set` 加 `null`——模型重建时
  `toJson` 会把未填字段重新写出来，删除无法生效，引擎会明确报错而不是假装成功。
- 对象值可以只写关心的键，其余键保留模型默认值（未写 = `null` = 未填写）。

### 两道校验

1. **往返核对**：补丁落在 JSON 上，再用 `ProjectDocument.fromJson` 重建，然后把目标
   路径读回来与请求值比对。枚举值拼错时项目模型会静默回退成默认值，这一步能把它
   变成 `invalid_value` 而不是假成功。
2. **无差异拦截**：改完与改前完全一致会被拒——这是键名拼错最典型的症状。

### 并发

所有工具带 revision。`propose` 校验 `baseRevision`，过期返回 `stale_revision`；
`apply` 提交 `patchId`（不重发 ops），取出即作废，避免客户端重试写两次；`propose`
之后项目被改动则返回 `conflict` → `stale_revision`。不自动合并、不自动重试。

`revision` 只存在于内存：`updateConfig` 与打开/新建项目各 +1，单调递增不重置。
不写进 `.pieproj`，不改 `formatVersion`。

## 授权与安全

- 默认关闭，需要用户在首页「AI 接入」里显式打开。
- 开启后 `apply` 直接改配置并自动保存，**不逐次弹确认**。这是有意取舍：确认卡片
  一直弹不出来会让自动化链路直接失效；授权交给开关，用户随时可关。
- 不信任某个客户端时：关掉开关停服，或点面板里的「重置令牌」让旧配置失效。
- 开关关闭、应用退出时立刻停服并删发现文件。
- 审计只记「时间、工具、结果码、revision 变化」，不记 token 与文档正文。
- 服务仅本机可达；局域网与公网都连不上。

## 验收

```powershell
cd packages/pieblock_mcp
dart analyze
dart test
dart run tool/mcp_smoke.dart     # 起服务 → 握手 → 读上下文 → propose → apply
```

冒烟脚本自带宿主、直接放行写入，覆盖完整链路与 stale revision 用例。

真机验收用 CodeBuddy：首页打开「AI 接入」→ 复制客户端配置 → 粘进客户端的 MCP
设置 → 重启客户端 → 让它读一次上下文并提一个改动 → 看 revision 是否 +1。

## 后续阶段（未实现）

1. 自动写入各客户端配置（注册表 + 探测 + 幂等回滚），这是「全自动接入」的部分。
2. `--mcp-stdio` 兼容壳，覆盖只接受 command 的客户端。
3. 会话上下文导出与 `PIEBLOCK_AGENT.md` 文本兜底，覆盖不支持 MCP 的客户端。
