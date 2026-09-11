# PIE-Block

PIE-Block 是面向 W.PIE RoboMaster 校内赛的 Windows 桌面集成开发环境。新版使用 Flutter 构建，通过分步向导帮助没有编程经验的同学完成机器人配置、生成代码、编译并烧录 STC32G 主控板。

## 当前版本

首版 Flutter 应用支持：

- 步兵机器人：遥控器、底盘、云台、拨弹、摩擦轮和按键配置；PWM 与引脚角色按硬件拓扑自动推导
- 工程机器人：1～4 个模式、轮换/一一对应切换和动态动作映射
- 调试工程：固定十路引脚的启停、排序、电机/舵机参数与安全摩擦轮渐变测试
- 音乐项目：原生钢琴卷帘作曲、MIDI 导入导出、P33 蜂鸣器方波预览和单音固件生成
- 字段范围、引脚占用、按键冲突和跨模式静态检查
- `.pieproj` 格式 15 项目文件，保存向导进度并以 500ms 防抖自动保存
- Material 3 浅色、深色和跟随系统主题
- 只读 C 代码预览、搜索、复制和导出 `main.c`
- 随应用发布的离线 SDCC C251，以及可选的本地 Keil C251 全量构建
- HEX 地址与校验和检查、按内容哈希复用构建结果、导出 HEX
- STC32G ROM USB-HID 主控板烧录、进度、取消和失败提示

暂不提供云端编译、串口/蓝牙烧录、AI 编辑、3D 仿真、Web、CLI 或 MCP。Android 可配置、编辑、预览和编译音乐项目；步兵/工程离线 SDCC 正在进行多进程真机黄金验证，Release 安全门通过前不对用户开放，且 Android 仍不支持 USB-HID 烧录。

## 项目结构

```text
./                       Flutter 应用（pubspec.yaml 位于仓库根目录）
packages/pieblock_core/  纯 Dart 项目模型、校验器与 C 生成器
packages/pieblock_toolchain/ Dart SDCC/Keil 构建、HEX 校验与产物缓存
packages/pieblock_hid/   Dart 烧录协议与 Windows 原生 HID 传输
packages/pieblock_sdcc_native/ Android C ABI 5 与多进程编译桥接
stc32g/                  STC32G 固件和硬件参考代码
stc32g_sdcc/             SDCC C251 支持库与离线测试
keil_server/             独立云编译服务（不由当前应用调用）
docs/                    硬件与项目格式文档
```

Flutter UI 不包含生成规则。`pieblock_core` 是配置、检查和代码生成的唯一实现。

## 开发

需要 Flutter stable，并启用 Windows Desktop：

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

三个 Dart 包可独立运行 `dart analyze` 与 `dart test`。Windows Release 产物位于 `build/windows/x64/runner/Release/`，发布时必须保留整个目录；`pieblock_hid.dll`、`data/pieblock_runtime` 和 `data/flutter_assets` 都是运行所必需的。

编译与主控板接线、开关位置和故障排查见 [Flutter 编译与烧录指南](docs/Flutter编译与烧录指南.md)。
Android 离线 SDCC 的架构、安全门和验收状态见 [Android SDCC 多进程移植](docs/android-sdcc-port.md)。

## 持续集成

`.github/workflows/windows.yml` 在 push / PR 到 `main` 以及手动触发时校验 Windows 构建，分两段执行：

1. **静态分析与单元测试**（ubuntu，约 2 分钟）：`pieblock_core`、`pieblock_hid`、`pieblock_toolchain` 三个包分别 `dart analyze` + `dart test`，再跑根目录的 `flutter analyze` + `flutter test`。
2. **Windows 构建与打包**（windows-latest，首次 20–35 分钟，工具链缓存命中后 5–8 分钟）：用 MSYS2 UCRT64 跑 `tools/prepare_sdcc_toolchain.ps1` 生成 Windows 版内置 SDCC 工具链（按 `sdcc-c251` 子模块提交缓存），校验 `bundle_manifest.json` 的平台字段，跑 `PIEBLOCK_RUN_SDCC_GOLDEN=1` 的 SDCC 金样比对，再 `flutter build windows --release` 并用 `tools/package_flutter_windows.ps1 -SkipBuild` 出安装包。

产物保留 14 天，名称为 `PIEBlock-<版本>-windows-setup.exe`（Inno 安装包）与 `PIEBlock-<版本>-windows-x64-release.zip`（免安装 `Release` 目录）。金样校验可用 `workflow_dispatch` 的 `skip_golden` 输入临时跳过。

本地复现 CI 的检查：

```powershell
git submodule update --init sdcc-c251
.\tools\prepare_sdcc_toolchain.ps1
$env:PIEBLOCK_RUN_SDCC_GOLDEN = '1'
Push-Location packages\pieblock_toolchain; dart test; Pop-Location
.\tools\package_flutter_windows.ps1
```

## 项目文件

新版继续使用 `.pieproj` 扩展名，但只接受 `format_version: 15`。格式 14 和旧 Godot 格式不会自动转换，需在新版中重新创建配置。新项目不预填任何必填配置；步兵云台轴默认各有一个未填执行器，可增删为多个或留空；调试工程预置十路停用引脚和 3 秒安全时长。音乐工程默认 480 PPQ、120 BPM 和 4/4 拍，可重新导入原始 MIDI。详细结构见 [项目文件格式](docs/Flutter项目文件格式.md)。
