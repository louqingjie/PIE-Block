# pieblock_core

PIE-Block 的纯 Dart 核心，提供格式 13 项目模型、步兵/工程静态检查、项目原子读写和 C 代码生成。

```dart
final config = InfantryConfig();
final issues = ProjectValidator.validate(config);
final code = CodeGenerator.generate(config);
```
