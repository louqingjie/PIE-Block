# Keil C251 编译集成说明

## 功能

桌面端（Electron）可将 Blockly 生成的 C 代码写入培训模板工程的 `main.c`，并调用本机 **Keil μVision (UV4)** + **C251** 工具链批编译，生成可烧录的 `Project_Template.hex`。

## 本机依赖

| 组件 | 说明 |
|------|------|
| Keil C251 | 本机已安装，注册表 `HKLM\SOFTWARE\WOW6432Node\Keil\Products\C251` |
| UV4 | 通常位于 `%LOCALAPPDATA%\Keil_v5\UV4\UV4.exe` |
| 工程模板 | 仓库内 `stc32g/Projects/0000.培训模板/` |

探测顺序：注册表 C251 路径 → `%LOCALAPPDATA%\Keil_v5` → `C:\Keil_v5` / `D:\Keil_v5` 等。

## 使用方式

1. 启动桌面端：`npm run dev:electron`（或打包后的安装程序）
2. 用积木拼好程序，确认右侧 C 代码正确
3. 点击顶栏 **编译**
4. 下方「Keil 编译日志」显示 UV4 输出；成功后可点 **打开 hex** 定位固件

### 手动指定 Keil 路径

若自动探测失败（安装在非常规目录）：

1. 点击顶栏 **Keil 路径**
2. 选择其一：
   - Keil 安装根目录（例如 `...\Keil_v5`，内含 `UV4`、`C251`）
   - 或直接选 `UV4.exe` / `C251.EXE`
3. 配置会写入应用 `userData/keil-config.json`，下次启动仍生效
4. 需要恢复自动探测时，点击 **重置路径**

状态栏会显示 `自动` / `手动` 来源。

浏览器里单独 `npm run dev` 时没有 Node/Keil，**编译**按钮会禁用。

## 编译流程（内部）

```text
生成 C 代码
  → 写入 stc32g/Projects/0000.培训模板/USER/src/main.c
  → UV4.exe -b Project_Template.uvproj -o pie_block_build.log
  → 读取 Objects/Project_Template.hex
```

成功判据：构建日志含 `0 Error(s)` 且 hex 文件存在。

## 相关文件

| 路径 | 作用 |
|------|------|
| `electron/keil-build.js` | 探测工具链、手动路径配置、写源码、调用 UV4 |
| `electron/main.js` | IPC：`keil:detect` / `keil:compile` / `keil:choosePath` / `keil:clearPath` |
| `electron/preload.cjs` | 暴露 `window.pieNative` |
| `%APPDATA%/…/keil-config.json` | 用户手动 Keil 路径（`userData`） |
| `src/main.js` | 编译按钮与日志 UI |
| `stc32g/Projects/0000.培训模板/MDK/Project_Template.uvproj` | Keil 工程 |

## 自检命令

```bash
node electron/test-keil-compile.mjs
```

应输出 `PASS` 并生成 hex。

## 打包注意

`package.json` 的 `build.extraResources` 会把 `stc32g` 拷入安装包（排除 Objects/Listings 等中间文件）。运行时从 `process.resourcesPath/stc32g` 读写工程。

**Keil 本身不随应用分发**，目标机器仍需自行安装 C251 工具链。

## 后续可扩展

- 一键烧录（STC-ISP / 串口下载）
- 选择其他工程模板（步兵/工程）
- 编译错误定位回 Blockly 积木
