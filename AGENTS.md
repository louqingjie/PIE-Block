# 首都师范大学 RoboMaster 机甲大师赛机器人图形化配置集成开发环境

请记得在合适时间提交Git并推送，提交信息需为中文，遵循 Conventional Commits，确保提交完没有未提交的内容，允许分多次提交

## 存档兼容（项目已正式发布）

项目文件 `.pieproj` 已随 1.7.0 正式发布，格式变更有硬性约束：

- **旧存档必须能打开**：`ProjectDocument.fromJson` 接受 `oldestSupportedFormatVersion`–`formatVersion` 的版本区间，新增字段一律可选并给默认值；升版时必须同步写迁移说明与回归样本（`packages/pieblock_core/test/fixtures/`）。
- **新版本写的存档旧版打不开**：拒绝文案要明确提示升级，不允许静默丢字段。
- 每次改 `formatVersion` 必须：重生成 `assets/templates/`、重存 `book/examples/`、更新格式文档与版本断言，并跑通兼容性用例。
- 行为层面同样向下兼容：生成代码、校验规则与 UI 默认值对旧存档保持原有含义，确需改变时必须提供迁移或明确提示。

## Flutter 工作流

仓库根目录即 Flutter 应用（标准 Flutter 工作区结构），常用命令：

```powershell
flutter pub get
flutter analyze
flutter test
```

Dart 包位于 `packages/` 下，可独立运行 `dart analyze` 与 `dart test`。集成测试位于 `integration_test/`，需在真机/桌面环境运行，不属于离线单元测试。
