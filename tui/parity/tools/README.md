# TUI golden 工具（开发期）

这里放**开发期**生成 `parity/golden/**` 的 Dart 脚本，仅用于把现有 Flutter 实现作为
“行为基准”导出快照；Rust 构建与发布产物不依赖 Dart。

## 生成模型 golden

```powershell
cd tui/parity/tools
dart pub get
dart run bin/export_model_goldens.dart
```

读取以下输入，输出到 `tui/parity/golden/model/`：

- `packages/pieblock_core/test/fixtures/*.pieproj`（格式 17–22 兼容样本）
- `assets/templates/*.pieproj`（当前格式 23 的四类工程模板）

每个 golden 包含源文件、kind、读取时的格式版本，以及迁移到当前格式后的
`ProjectDocument.toJson()`。

## 生成校验器 golden

```powershell
cd tui/parity/tools
dart run bin/export_validation_goldens.dart
```

输出到 `tui/parity/golden/validation/`：输入为模板、调试 fixture、四类工程的默认
文档，以及一组有意构造的非法/边界配置；每个 golden 包含文档 JSON、完整 `issues`
（以及机器人类工程的 `remoteIssues` 子集）。Rust 侧先用完整列表对拍调试工程，
公共机器人规则对拍 remote 子集，步兵/工程专属规则移植后扩展到完整列表。

> 后续代码生成/CLI 的 golden 也放在这里生成；生成结果提交到 git，
> Rust 测试只读快照，不需要安装 Dart。

