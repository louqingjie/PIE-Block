# Pie-Block

Pie-Block 是面向 W.PIE RoboMaster 校内赛的 Windows 桌面代码生成器。新版使用 Flutter 构建，通过分步向导帮助没有编程经验的同学完成机器人配置，并生成 STC32G `main.c`。

## 当前版本

首版 Flutter 应用支持：

- 步兵机器人：遥控器、底盘、PWM、云台、拨弹、摩擦轮和按键配置
- 工程机器人：1～4 个模式、轮换/一一对应切换和动态动作映射
- 字段范围、引脚占用、按键冲突和跨模式静态检查
- `.pieproj` 格式 12 项目文件，500ms 防抖自动保存
- Material 3 浅色、深色和跟随系统主题
- 只读 C 代码预览、搜索、复制和导出 `main.c`

暂不提供调试/音乐项目、编译、烧录、AI 编辑、3D 仿真、Android、Web、CLI 或 MCP。

## 项目结构

```text
apps/pieblock_app/       Flutter Windows 桌面应用
packages/pieblock_core/  纯 Dart 项目模型、校验器与 C 生成器
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
cd apps/pieblock_app
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

核心包可独立运行 `dart analyze` 与 `dart test`。Windows Release 产物位于 `apps/pieblock_app/build/windows/x64/runner/Release/`。

## 项目文件

新版继续使用 `.pieproj` 扩展名，但只接受 `format_version: 12`。旧 Godot 格式不会自动转换，需在新版中重新创建配置。详细结构见 [项目文件格式](docs/Flutter项目文件格式.md)。
