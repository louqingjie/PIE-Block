# Keil C251 编译集成说明

## 功能

桌面端（Electron）可将 Blockly 生成的 C 代码写入培训模板工程的 `main.c`，并调用 **Keil μVision (UV4)** + **C251** 工具链批编译，生成可烧录的 `Project_Template.hex`。

## 工具链来源（优先级）

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | **内置** | `vendor/keil-toolchain`（开发）或安装包 `resources/keil-toolchain`（打包） |
| 2 | **手动** | 用户通过「Keil 路径」指定，写入 `userData/keil-config.json` |
| 3 | **自动** | 注册表 + 常见安装目录（如 `%LOCALAPPDATA%\Keil_v5`） |

状态栏显示 `C251 … · 内置 / 手动 / 自动`。

> **授权**：内置二进制为 Keil 商业软件。仅在你已有**可再分发授权**时再提交/打包。  
> 本仓库**跟踪** `vendor/keil-toolchain/`（约 120MB+）；克隆后可直接使用内置编译。  
> 仍可用 `npm run prepare:keil` 从本机 Keil 刷新工具链。

## 开发者：准备内置工具链

在已安装 Keil C251 的 Windows 机器上：

```bash
# 从本机 Keil_v5 同步最小子集到 vendor/keil-toolchain
npm run prepare:keil
# 或
node scripts/prepare-keil-toolchain.mjs --source "C:\Users\<you>\AppData\Local\Keil_v5" --force
```

检查：

```bash
npm run check:keil
```

自检编译（强制只用内置，模拟无系统 Keil）：

```bash
npm run test:keil:bundled
```

应输出 `PASS` 并生成 hex。

### 内置目录结构

```text
vendor/keil-toolchain/
  TOOLS.INI          # 运行时改写 PATH 为绝对路径
  UV4/UV4.exe …
  C251/BIN/C251.EXE, L251.EXE, OH251.EXE, A251.EXE …
  C251/INC/…
  C251/LIB/…
  bundle-manifest.json
```

`prepare` 会排除 ARM 工具链、armlm、FlexNet 大工具、chm 文档等，以控制体积。

## 使用方式

1. 启动桌面端：`npm run dev:electron`（或打包后的安装程序）
2. 用积木拼好程序，确认右侧 C 代码正确
3. 点击顶栏 **编译**
4. 下方「Keil 编译日志」显示 UV4 输出；成功后可点 **打开 hex** 定位固件

### 手动指定 Keil 路径（回退）

若内置不可用或需覆盖：

1. 点击顶栏 **Keil 路径**
2. 选择 Keil 根目录或 `UV4.exe` / `C251.EXE`
3. 配置写入 `userData/keil-config.json`
4. **重置路径** 清除手动配置（恢复内置/自动）

浏览器里单独 `npm run dev` 时没有 Node/Keil，**编译**按钮会禁用。

## 编译流程（内部）

```text
生成 C 代码
  → （内置时）改写 keil-toolchain/TOOLS.INI 中 C251/UV2 PATH
  → 写入 stc32g/Projects/0000.培训模板/USER/src/main.c
  → UV4.exe -b Project_Template.uvproj -o pie_block_build.log
  → 读取 Objects/Project_Template.hex
```

成功判据：构建日志含 `0 Error(s)` 且 hex 文件存在。

## 相关文件

| 路径 | 作用 |
|------|------|
| `electron/keil-build.js` | 内置/手动/自动探测、TOOLS.INI、写源码、UV4 批编译 |
| `electron/main.js` | IPC：`keil:detect` / `keil:compile` / `keil:choosePath` / `keil:clearPath` |
| `electron/preload.cjs` | 暴露 `window.pieNative` |
| `scripts/prepare-keil-toolchain.mjs` | 从本机 Keil 同步内置工具链 |
| `scripts/check-keil-toolchain.mjs` | 打包前完整性检查 |
| `vendor/keil-toolchain/` | 内置工具链（Git 跟踪；需合法授权） |
| `src/main.js` | 编译按钮与状态 UI |
| `stc32g/Projects/0000.培训模板/MDK/Project_Template.uvproj` | Keil 工程 |

## 自检命令

```bash
npm run test:keil              # 内置优先，否则系统 Keil
npm run test:keil:bundled      # 仅内置
```

## 打包注意

`package.json` 的 `build.extraResources` 会把：

- `stc32g` → `resources/stc32g`
- `vendor/keil-toolchain` → `resources/keil-toolchain`

`npm run pack` / `npm run dist` 会先执行 `check:keil`；缺少内置工具链则打包失败。

运行时：

- 工程：`process.resourcesPath/stc32g`
- 工具链：`process.resourcesPath/keil-toolchain`

若安装目录只读导致无法写 `TOOLS.INI`，开发/解包目录一般可写；若失败请查看编译日志中的 TOOLS.INI 提示，或改用「Keil 路径」指向可写副本。

## 后续可扩展

- 一键烧录（STC-ISP / 串口下载）
- 纯 CLI（C251/L251/OH251）不依赖 UV4
- 选择其他工程模板（步兵/工程）
- 编译错误定位回 Blockly 积木