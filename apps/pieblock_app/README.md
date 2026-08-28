# pieblock_app

PIE-Block 的 Flutter Windows 桌面前端。项目模型与代码生成来自 `pieblock_core`，固件构建来自 `pieblock_toolchain`，主控板 USB-HID 烧录来自 `pieblock_hid`。

```powershell
flutter run -d windows
flutter test
flutter build windows --release
```

Release 构建会把内置 SDCC、步兵/工程固件模板和 `pieblock_hid.dll` 一起放入发布目录。不能只复制 `PIE-Block.exe`。

## Windows 安装包

```powershell
tools\package_flutter_windows.ps1
```

脚本自动完成：读取 `pubspec.yaml` 版本号 → `flutter build windows --release` → 校验 Release 产物完整性 → 调用 Inno Setup 6（ISCC.exe）生成 `output\PIEBlock-<版本>-windows-setup.exe`。

参数：

- `-SkipBuild`：复用已有 Release 产物，跳过 flutter build
- `-OutputBaseName <名称>`：覆盖默认安装包文件名（不含扩展名）
- `-Iscc <路径>`：ISCC.exe 路径，默认自动探测常见安装位置

安装脚本位于 `windows/installer/pieblock.iss`（简体中文界面，语言文件 `ChineseSimplified.isl` 随仓库提供）。
