# PIE-Block 接入（DSH 插件）

把正在运行的 PIE-Block 桌面端接到 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）。
安装一次，之后 PIE-Block 开着就自动连上，关掉就自动断开——不需要复制地址和令牌，也不需要改 DSH 的配置。

## 它做什么

PIE-Block 已经自带 MCP 服务（`packages/pieblock_mcp`）：本机回环地址上的六个项目工具，用应用自己的 token 鉴权，
由首页「AI 接入（MCP）」开关决定是否存在。这个插件做的是**发现与转交**：

1. 轮流读取 PIE-Block 的运行时发现文件 `mcp-bridge.json`（含 endpoint、token、pid）；
2. 文件有效时调用 `ctx.mcpManager.register()` 注册为 `mcp__pieblock__*` 工具；
3. 文件消失（应用退出或开关关闭）时撤回注册，工具随之消失；
4. 端口、token、pid 任一变化（重启、重置令牌）时重建注册，不需要人工重配。

它不启动 PIE-Block，不写 PIE-Block 的任何文件，也不改 DSH 的配置。

## 安装

发布到 npm 后，在 DSH 的 **插件 → 添加插件** 里输入包名：

```text
pieblock-dsh-mcp
```

开发期可以直接安装本目录（绝对路径），DSH 会以链接方式加载：

```text
<仓库根>/integrations/dsh-mcp
```

启用后不需要任何配置。等 PIE-Block 里打开「AI 接入（MCP）」，新会话里就能看到 `mcp__pieblock__pieblock_handshake` 等工具。

## 配置（可选）

在 DSH 的 profile patch 里给 `pieblock-mcp` 行加 `config`：

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `serverName` | `pieblock` | 工具前缀，需匹配 `[A-Za-z0-9_-]{1,32}`；改名后工具名也跟着变 |
| `bridgePath` | 空 | 显式指定发现文件路径；空则按平台自动查找 |
| `pollMs` | `2000` | 轮询间隔（毫秒，最小 50） |
| `startupTimeoutMs` | `8000` | 单次连接预算，传给 mcp-client |

发现文件的默认位置：

| 平台 | 路径 |
| --- | --- |
| Windows | `%APPDATA%\com.wpie\PIE-Block\mcp-bridge.json` |
| macOS | `~/Library/Application Support/com.wpie/PIE-Block/mcp-bridge.json` |
| Linux | `$XDG_DATA_HOME/com.wpie/PIE-Block/mcp-bridge.json` |

便携版或改过数据目录的安装，用环境变量 `PIEBLOCK_MCP_BRIDGE` 指向实际文件即可。

## 安全边界

- 只接受 `http://127.0.0.1` / `localhost` / `[::1]` 的端点：发现文件里写着 token，不能让被篡改的文件把它发到别的主机。
- 读出直连，不经过网络；插件不上报任何数据。
- 写入权限来自 PIE-Block 的开关本身：关掉开关或退出应用，服务与工具一起消失。
- 若你已经在 DSH 设置里手动配了同名 `pieblock` 服务器，插件会打印一条警告并让位，不做两份注册。

## 开发自测

```powershell
cd integrations/dsh-mcp
node tool/smoke.mjs
```

离线验证注册 / 换令牌 / 应用退出 / 崩溃残留 pid / 非回环端点 / 插件卸载六种情况，不依赖 DSH，也不碰真实应用数据。

## 限制

- 只支持桌面端的 PIE-Block；网页版与手机版没有本地 MCP 服务。
- 需要 DSH 提供 `mcpManager` 服务（Standard / Creator 等带 MCP 管理的 profile 都有）。开发时对照 0.2.2-rc.3 验证。
- 插件是「发现者」：应用没开、开关没开，就没有工具；这是有意为之，不替用户做开关注入。
