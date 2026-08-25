# pieblock_core

PIE-Block 的纯 Dart 核心，提供格式 14 项目模型、向导进度、步兵/工程静态检查、项目原子读写和 C 代码生成。

```dart
final config = InfantryConfig(); // 必填项默认均为空
final issues = ProjectValidator.validate(config);
// 仅在 issues 中没有 Error 时生成；不完整配置会抛出 StateError。
final code = CodeGenerator.generate(config);
```
