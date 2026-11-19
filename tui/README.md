# PIE-Block TUI（M0 技术验证）

用 Rust 复刻 PIE-Block 桌面端功能与 UI 信息内容的终端版本。完整计划见
[`docs/design/TUI复刻实现计划.md`](../docs/design/TUI复刻实现计划.md)。

- 语言/框架：Rust 2024 + ratatui 0.30 + crossterm 0.29。
- 平台：Windows 10/11 x64、Linux x64（macOS 不在 1.0 范围）。
- 当前阶段：**M0 技术验证**（应用骨架、CJK/宽字符、键鼠、表单/卷帘原型、hidapi/SDCC 原型）。
- 发布产物不含 Dart/Flutter 运行时。

## 开发

```powershell
cd tui
cargo run -p pieblock-tui        # 启动 TUI（默认启用鼠标捕获；可用 --no-mouse 关闭）
cargo run -p pieblock-tui -- --diagnostics  # 打印发布验收用环境诊断（不启动 TUI）
.\run.ps1 -Diagnostics                      # 同上（脚本会自动定位 cargo；-Version 打印版本）
cargo test                       # 单元测试
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo run -p pieblock-cli -- describe
```

如果终端提示 `cargo` 不是命令（Rust 安装后旧终端不会自动刷新 PATH），任选一种方式：

```powershell
# 方式一：当前终端临时补 PATH
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
cargo run -p pieblock-tui

# 方式二：使用仓库内启动脚本（自动定位 cargo）
.\run.ps1
.\run.ps1 -NoMouse

# 方式三：绝对路径
& "$env:USERPROFILE\.cargo\bin\cargo.exe" run -p pieblock-tui
```

cmd 用户可用 `run.cmd`，或先执行 `set PATH=%USERPROFILE%\.cargo\bin;%PATH%`。
彻底解决：重新打开一个终端；若仍无效，重启资源管理器或注销后重新登录，让新进程继承更新后的用户 PATH。

最低终端 80×24，推荐 120×36；Windows 建议使用 Windows Terminal（conhost 的宽字符/色彩支持较弱）。按 `F1` 或 `?` 查看键位。

## 目录

```text
crates/pieblock-core       领域模型/校验/代码生成（M1 起逐步移植）
crates/pieblock-toolchain  SDCC/Keil 构建与缓存（M2）
crates/pieblock-hid        USB-HID 烧录协议（M2）
crates/pieblock-ui         TUI 主题/组件/布局
crates/pieblock-tui        主程序（当前 M0 演示壳）
crates/pieblock-cli        只读 CLI（validate/codegen/describe）
```

## 发布包

```powershell
# Windows x64
pwsh -File scripts/package.ps1
# 复用已构建的 release：pwsh -File scripts/package.ps1 -SkipBuild

# Linux x86_64
SKIP_BUILD=1 ./scripts/package.sh
```

产物在 `tui/dist/`：`PIE-Block-TUI-<版本>-<平台>.zip|tar.gz` 与 `.sha256`。包内布局：

```text
pieblock-tui(.exe)              主程序
data/pieblock_runtime/          SDCC 工具链与 stc32g_sdcc 固件支撑（构建/烧录使用）
assets/templates/               新建工程模板
THIRD_PARTY_NOTICES.txt         SDCC 等第三方组件声明
README.md
```

发布产物不包含 Dart/Flutter 运行时（打包脚本会扫描 `.dart/.dill/libapp*/flutter_*` 并拒绝）。服务端 CI 见 `.github/workflows/tui.yml`，每次推送构建并上传 Windows/Linux 发布包。
