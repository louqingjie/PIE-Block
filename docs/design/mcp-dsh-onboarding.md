# 把 PIE-Block 的 MCP 接入 DSH：门槛比较与推荐路径

PIE-Block 的 MCP 服务已经在桌面端跑通（见 [AI 接入（MCP）](mcp-ai-bridge.md)），剩下的问题是
**用户怎么把它接到 DSH 上**。本文比较几种接法，并说明推荐方案与落地位置。

## 现状

- 服务只绑 `127.0.0.1`，路径固定 `/mcp`，用随安装生成的 token 鉴权（也接受 `?token=`）。
- 运行时发现文件 `mcp-bridge.json` 写在应用数据目录：`endpoint`、`token`、`pid`、`startedAt`；
  开关关闭或应用退出时删除，**重启后端口与 token 不变**。
- 应用内「复制客户端配置」给出的是 Claude 风格的 `{"mcpServers":{...}}`，DSH 不读这种结构。

## 三条路径

| 路径 | 用户操作 | 令牌/端口变化后 | 可维护性 |
| --- | --- | --- | --- |
| A. 手动填 DSH 设置 | 打开设置 → MCP → 新建条目 → 粘贴 URL（可带 `?token=`） | 失配后要重贴 | 零代码，但每次 token 轮换都要人工介入 |
| B. 安装 DSH 插件（自动发现） | 装一次插件，之后什么都不做 | 自动重建注册 | 代码量小，长期零维护 |
| C. 应用直接改 DSH 配置 | 点「接入 DSH」 | 取决于我们写入的逻辑 | 与 DSH 版本、profile 布局强耦合，失败难回滚 |

C 是**不推荐**的：DSH 的 profile 安装由它自己的插件管理器负责（pnpm 安装、bundle 选择、
版本兼容检查），外部进程照着写配置既容易在升级后失效，也违背本项目「不改写第三方客户端配置」
的既有边界。

## 推荐：A + B 两层

**A 层（立刻可用，零安装）**：PIE-Block 的 AI 接入面板增加一个「复制 DSH 服务器地址」，
内容是 `http://127.0.0.1:47173/mcp?token=…`。用户把它粘进 DSH 的「设置 → MCP」即可。
适合只想试一次、或本来就在 DSH 设置里手工管理 MCP 的用户。

**B 层（推荐默认）**：发布一个 DSH 插件包，安装一次，之后自动跟随应用的启停与令牌轮换。
代码在 [`integrations/dsh-mcp/`](../../integrations/dsh-mcp/README.md)：

- 插件声明 `inject: ['mcpManager']`，定期读 `mcp-bridge.json`；
- 有效时调用 `ctx.mcpManager.register('pieblock', {...})`，工具以 `mcp__pieblock__*` 出现；
- 文件消失、`pid` 不再存活、发现文件非法时撤回注册；
- `endpoint` / `token` / `pid` / `startedAt` 任一变化都重建注册，覆盖重启与「重置令牌」；
- 只接受回环地址，避免被篡改的发现文件把 token 送去远端；
- 不启动应用、不写应用文件、不改 DSH 配置。

用户侧只有一步：在 DSH 的「插件 → 添加插件」里输入包名（发布到 npm 后），或在插件索引
（实验性「自定义插件索引」）里点安装。之后在 PIE-Block 打开「AI 接入（MCP）」即可。

## 为什么 B 层要读发现文件，而不是写死 URL

token 每次安装随机生成、用户可随时重置；端口在默认端口被占用时也会变。把它写进插件包或
DSH 配置，第一次轮换就失效。发现文件本来就是为「客户端自己找上门」设计的，插件复用它，
用户就永远不用再复制任何东西。

## 验证记录

- **协议兼容**：用 DSH 自带的 `@modelcontextprotocol/client`（2.2.0，运行在 Desktop 0.2.2-rc.3）
  直连 PIE-Block 的 Dart 服务：`initialize` 协商到 `2025-06-18`，`tools/list` 返回六个工具，
  `pieblock_handshake` 与 `pieblock_get_context` 正常返回。说明自定义的 Streamable HTTP
  实现（纯 JSON 响应、无 SSE、无 session 头）能被 DSH 的官方 SDK 接受。
- **插件链路**：`node integrations/dsh-mcp/tool/smoke.mjs` 覆盖注册、换令牌、应用退出、
  崩溃残留 pid、非回环端点、插件卸载六种情况，全部通过（离线，不依赖 DSH 与真实应用数据）。
- **未验证**：插件在真实 DSH profile 中的安装与工具出现，需要一次实际安装后确认。

## 后续

1. 发布 `pieblock-dsh-mcp` 到 npm，并在 README / 官网写清安装步骤。
2. 应用内 AI 接入面板：加「复制 DSH 地址」，并把插件安装步骤写进文案。
3. 可选：把插件登记进 PIE-Block 自己的插件索引，DSH 用户可在「发现」页一键安装。
