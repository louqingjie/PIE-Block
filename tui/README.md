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
cargo test                       # 单元测试
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo run -p pieblock-cli -- describe
```

最低终端 80×24，推荐 120×36。按 `F1` 或 `?` 查看键位。

## 目录

```text
crates/pieblock-core       领域模型/校验/代码生成（M1 起逐步移植）
crates/pieblock-toolchain  SDCC/Keil 构建与缓存（M2）
crates/pieblock-hid        USB-HID 烧录协议（M2）
crates/pieblock-ui         TUI 主题/组件/布局
crates/pieblock-tui        主程序（当前 M0 演示壳）
crates/pieblock-cli        只读 CLI（validate/codegen/describe）
```
