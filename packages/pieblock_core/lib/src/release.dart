/// PIE-Block 应用发布版本（major.minor.patch），与仓库根 `pubspec.yaml` 的
/// `version` 前缀保持一致。
///
/// CLI 由应用同一发版流程构建，`describe.release` 用它告诉调用方「这份 CLI 对应
/// 哪个 PIE-Block 发布版本」；CLI 自身的 [cliVersion] 只是工具契约版本，二者不要
/// 混用。改根 pubspec 版本时必须同步这里（`test/release_version_test.dart` 会守护）。
const String pieblockRelease = '1.9.0';
