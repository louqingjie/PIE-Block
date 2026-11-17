/// 应用版本号。
///
/// 与 `pubspec.yaml` 的 `version` 保持同一值，由 `test/version_test.dart`
/// 断言，避免两处各写一遍而漂移。MCP 握手会把它报给外部客户端。
const appVersion = '1.8.0';
