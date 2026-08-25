# pieblock_app

PIE-Block 的 Flutter Windows 桌面前端。项目模型与代码生成来自 `pieblock_core`，固件构建来自 `pieblock_toolchain`，主控板 USB-HID 烧录来自 `pieblock_hid`。

```powershell
flutter run -d windows
flutter test
flutter build windows --release
```

Release 构建会把内置 SDCC、步兵/工程固件模板和 `pieblock_hid.dll` 一起放入发布目录。不能只复制 `pieblock_app.exe`。
