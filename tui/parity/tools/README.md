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
（以及机器人类工程的 `remoteIssues` 子集）。当前对比口径：

- 调试工程、步兵工程、工程（engineer）：完整 `issues` 列表逐条一致（工程含 PWM/模式/
  动作行/动作表/摩擦轮规则；音乐校验规则待移植后同样扩展为完整列表）。

> 后续代码生成/CLI 的 golden 也放在这里生成；生成结果提交到 git，
> Rust 测试只读快照，不需要安装 Dart。

## 生成表达式 golden

```powershell
cd tui/parity/tools
dart run bin/export_expression_goldens.dart
```

输出 `tui/parity/golden/expression/expression.json`：60+ 条表达式（合法/非法）的
诊断、类型、C 代码、helpers、求值结果，6 组运行时 helper 完整代码，变量名合法性
用例，以及工程模板逐模式的试算结果。

## 生成 C 代码生成 golden

```powershell
cd tui/parity/tools
dart run bin/export_codegen_goldens.dart
```

输出 `tui/parity/golden/codegen/codegen.json`：9 份 fixture + 4 份模板 + 4 类默认
文档的生成源码、表达式行号映射；配置未通过校验时记录 Dart 抛出的错误文案。
Rust 侧目前对拍调试/步兵全部用例，工程与音乐随移植推进扩展。

