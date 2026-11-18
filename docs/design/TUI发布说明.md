# PIE-Block TUI 发布说明

## 1. 版本与平台

- 当前版本：`0.1.0`（TUI 复刻线，独立于 Flutter 桌面端版本号）。
- 支持平台：Windows 10/11 x64、Linux x86_64（macOS 不在 1.0 范围）。
- 运行时依赖：无（发布包内自带 SDCC 工具链与 stc32g_sdcc 固件支撑）。
- 终端要求：最低 80×24，推荐 120×36；Windows 建议 Windows Terminal。

## 2. 发布包内容

```text
pieblock-tui(.exe)              主程序（鼠标默认开启，--no-mouse 关闭）
data/pieblock_runtime/          sdcc-toolchain/ 与 stc32g_sdcc/（真实构建使用）
assets/templates/               新建工程模板（步兵/工程/调试/音乐）
THIRD_PARTY_NOTICES.txt         SDCC 等第三方组件声明
README.md                       使用说明
```

程序启动时按以下顺序定位运行时资源：`PIEBLOCK_RUNTIME_ROOT` 环境变量 → 可执行文件旁
`data/pieblock_runtime` → 当前目录及其祖先目录（开发态仓库根）。

## 3. 构建与打包

```powershell
# Windows x64
pwsh -File tui/scripts/package.ps1
pwsh -File tui/scripts/package.ps1 -SkipBuild   # 复用 target/release

# Linux x86_64
tui/scripts/package.sh
SKIP_BUILD=1 tui/scripts/package.sh
```

产物：`tui/dist/PIE-Block-TUI-<版本>-<平台>.zip|tar.gz` + `.sha256`。

打包脚本强制校验发布产物不含 Dart/Flutter 运行时：出现 `.dart`、`.dill`、`libapp*`、
`flutter_*`、`libflutter*` 或 `flutter/`、`dart-sdk/`、`.dart_tool/` 即中止。

## 4. CI

`.github/workflows/tui.yml` 在 Windows/Linux 上执行：

1. `cargo fmt --all --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test`（含真实 SDCC 构建测试；缺少工具链的环境会自动跳过真机构建用例）
4. `cargo build --release`
5. 运行平台打包脚本，校验无 Dart/Flutter 文件
6. 上传 `PIE-Block-TUI-Windows` / `PIE-Block-TUI-Linux` 工件（zip/tar.gz + sha256）

## 5. 发布前人工验收清单

- [ ] Windows Terminal 与 conhost：CJK/宽字符、IME、鼠标滚轮/点击、Alt 屏幕恢复。
- [ ] Linux（GNOME Terminal / konsole）：CJK 字体回退、鼠标、SDL 无依赖。
- [ ] 真实主控板 USB-HID 烧录（设备探测/擦除/写入/校验/复位；中断与重试）。
- [ ] SDCC 真实构建 HEX 与 Flutter 桌面端 SHA-256 对照（同配置、同工具链版本）。
- [ ] Keil C251 编译器路径与构建（当前 Rust 工具链仅实现 SDCC；Keil 明确提示未移植）。
- [ ] 旧 `.pieproj`（格式 17–23）打开/保存字节一致性回归。

未完成项会记录在 `docs/design/TUI复刻进度.md`，不得在发布说明中隐藏。
