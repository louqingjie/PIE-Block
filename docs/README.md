# 文档索引

本目录收录本项目的硬件、协议、工具链与排障文档：应用本体是仓库根目录的 Flutter 工程，
这里只回答「怎么用」「为什么这样实现」「出了问题怎么办」。

## 分类导航

| 目录 | 内容 | 代表文档 |
| --- | --- | --- |
| [`guides/`](guides/) | 面向操作者的「怎么做」指南 | [RM 电控指南](guides/RM电控指南.md) |
| [`reference/`](reference/) | 规范与字段定义 | [项目文件格式](reference/Flutter项目文件格式.md) |
| [`reference/schemas/`](reference/schemas/) | 各项目类型的 JSON Schema（由 CLI `schema` 命令生成，与代码同步） | [infantry.schema.json](reference/schemas/infantry.schema.json) |
| [`design/`](design/) | 实现说明与技术报告 | [Android SDCC 多进程移植](design/android-sdcc-port.md) |
| [`releases/`](releases/) | 发布说明（发版时 CI 取 `docs/releases/<版本>.md` 作为 Release 正文） | [1.2.1](releases/1.2.1.md) |
| [`pitfall/`](pitfall/) | 具体故障案例（绑定到出现该问题的版本） | [SDCC 组帧低字节丢失](pitfall/sdcc-组帧低字节丢失.md)、[HID 烧录写块无响应](pitfall/HID烧录写块无响应.md) |
| [`playbook/`](playbook/) | 可复用的排障流程 | [拓展板通信排障](playbook/拓展板通信排障.md) |
| [`legal/`](legal/) | 第三方声明与许可证 | [第三方声明](legal/THIRD_PARTY_NOTICES.md) |
| [`examples/`](examples/) | 示例文件 | [music.json](examples/music.json) |
| [`assets/`](assets/) | 文档插图 | [智能交互手柄](assets/智能交互手柄/) |

## 先读哪几篇

新手按这条路径读：

1. [机械拓展板使用指南](guides/机械拓展板使用指南%20.md) —— 硬件接线与端口用途
2. [RM 电控指南](guides/RM电控指南.md) —— 主控板如何通过 UART 驱动拓展板
3. [Flutter 编译与烧录指南](guides/Flutter编译与烧录指南.md) —— 编译、接线与烧录
4. [项目文件格式](reference/Flutter项目文件格式.md) —— `.pieproj` 字段与结构

## guides（怎么做）

- [Flutter 编译与烧录指南](guides/Flutter编译与烧录指南.md)
- [机械拓展板使用指南](guides/机械拓展板使用指南%20.md)
- [RM 电控指南](guides/RM电控指南.md)
- [代码生成器 CLI 与 MCP 接入指南](guides/代码生成器CLI与MCP接入指南.md)
- [汇编生成器](guides/汇编生成器.md)
- [公网部署 Cloudflare Tunnel 指南](guides/公网部署CloudflareTunnel指南.md)
- [服务器新机部署指南](guides/服务器新机部署指南.md)
- [智能交互手柄](guides/智能交互手柄.md)

## reference（规范与字段定义）

- [STC32G 固件约束](reference/STC32G固件约束.md)
- [Flutter 项目文件格式](reference/Flutter项目文件格式.md)
- schemas：[debug](reference/schemas/debug.schema.json)、[engineer](reference/schemas/engineer.schema.json)、[infantry](reference/schemas/infantry.schema.json)、[music](reference/schemas/music.schema.json)

## design（实现说明 / 技术报告）

- [STC32G 无线固件升级技术报告](design/STC32G无线固件升级技术报告.md)
- [Android SDCC 多进程移植](design/android-sdcc-port.md)

## releases（发布说明）

- [1.1.0](releases/1.1.0.md)
- [1.2.0](releases/1.2.0.md)
- [1.2.1](releases/1.2.1.md)

## pitfall（故障案例）

- [SDCC 组帧低字节丢失](pitfall/sdcc-组帧低字节丢失.md)
- [USB-HID 烧录在第二块（0x0080）设备无响应](pitfall/HID烧录写块无响应.md)

## playbook（排障流程）

- [拓展板通信排障](playbook/拓展板通信排障.md)

## legal（第三方声明与许可证）

- [第三方声明](legal/THIRD_PARTY_NOTICES.md)
- 许可证原文：[JetBrainsMono-OFL-1.1](legal/licenses/JetBrainsMono-OFL-1.1.txt)、[OpenCode-LICENSE](legal/licenses/OpenCode-LICENSE.txt)

## 归档约定

- `guides/`、`reference/`、`design/` 放稳定知识：操作步骤、规范定义、实现说明。它们随代码演进而更新，不绑定具体版本。
- `pitfall/` 放具体故障案例，通常**绑定到出现该问题的版本**（如某次编译/通信异常的现象、根因证据与规避要点）。
- `playbook/` 放可复用的排障流程，与 `pitfall/` 中的具体案例**互链**：案例给出「当时发生了什么」，流程给出「以后遇到同类问题怎么排查」。
- `releases/` 放发布说明；**CI 会读取该路径**（`docs/releases/<版本>.md`）作为 GitHub Release 正文，发版时必须同步提交对应版本文件。
- `assets/` 放文档插图，按主题分子目录。
