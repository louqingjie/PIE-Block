请记得在合适时间提交Git并推送，提交信息需为中文，遵循 Conventional Commits，确保提交完没有未提交的内容，允许分多次提交
目前项目仍在快速迭代，还未正式发布，无需考虑向下兼容的问题

## Flutter 工作流

仓库根目录即 Flutter 应用（标准 Flutter 工作区结构），常用命令：

```powershell
flutter pub get
flutter analyze
flutter test
```

Dart 包位于 `packages/` 下，可独立运行 `dart analyze` 与 `dart test`。集成测试位于 `integration_test/`，需在真机/桌面环境运行，不属于离线单元测试。
