# 第三方软件声明

## SDCC MCS-251 / C251 工具链

Windows 发布版内嵌由 `sdcc-c251` 子模块构建的 SDCC MCS-251 工具链。

- 源代码：https://github.com/louqingjie/sdcc-c251
- 准确源码版本：见应用内 `vendor/sdcc-toolchain/bundle_manifest.json` 的
  `source_commit`，并与主仓库的 `sdcc-c251` 子模块指针一致。
- 许可证：GNU GPL 及工具链目录内各组件许可证；发布包同时包含 `COPYING`、
  `COPYING3` 和上游 `README.md`。

发布者必须长期保留对应提交的完整源代码，并在发布二进制时按适用许可证提供获取方式。

## OpenCode

Windows 发布版内嵌 OpenCode CLI `1.18.14` 的官方 Windows x64 二进制。

- 项目主页：https://github.com/anomalyco/opencode
- 官方发布物：https://github.com/anomalyco/opencode/releases/tag/v1.18.14
- 许可证：MIT，完整文本见 `docs/licenses/OpenCode-LICENSE.txt`
- 准确版本与 SHA-256：见应用内 `vendor/opencode-runtime/bundle_manifest.json`

OpenCode 的自动更新由 PIEBlock 禁用；经过兼容性验证的新版本将随 PIEBlock 更新发布。
