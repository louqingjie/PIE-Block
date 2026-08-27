# PIE-Block Flutter 编译与烧录指南

## 编译器

“生成代码”通过后进入最后的“编译与烧录”步骤。默认的“内置 SDCC C251”无需安装其他软件，可以离线编译步兵和工程项目。第一次使用时，应用会把经过版本和哈希校验的工具链部署到：

```text
%LOCALAPPDATA%\PIE-Block\runtime
```

也可以选择“本地 Keil C251”。指定的目录必须包含：

```text
UV4\uVision.com（或 UV4.exe）
C251\BIN\C251.EXE
```

PIE-Block 始终调用 Keil 的 `-r` 全量重建，避免不同机器人配置复用旧目标文件。如果日志出现 `RESTRICTED VERSION`、`LICENSE ERROR` 或 `ERROR L250`，需要为当前电脑配置有效的 C251 许可证。应用只有在用户明确提交密钥后才修改 `TOOLS.INI`，写入前会创建 `.pieblock.bak`，也可以直接使用 Keil License Management。

成功固件缓存于 `%LOCALAPPDATA%\PIE-Block\builds`。源码、项目类型、编译器或工具链版本发生变化后，旧固件立即失效；应用不会把 HEX 写入 `.pieproj`。

## 主控板接线与开关

烧录只支持 STC32G 主控板 ROM 的 USB-HID ISP：

- VID：`34BF`
- PID：`1001`
- 标准 HID，Windows 不需要安装额外驱动
- 不支持串口、蓝牙、Python 烧录器或任意外部 HEX

机械扩展板已经烧录好专用程序，绝不能选择或尝试给扩展板烧录。

连接 USB 前关闭四个开关：

1. 主控板 `SERVO`
2. 主控板 `POWER`
3. 扩展板 `POWER`
4. 扩展板 `BOOSTER`

主控板只能在断电后重新上电时进入 ROM ISP。烧录成功后芯片自动复位并从 HID 设备列表消失，这是正常现象；再次烧录必须重新断电上电。

## 操作说明

- “仅编译”：强制重新生成 HEX，不连接硬件。
- “编译并烧录”：没有匹配固件时先编译，成功后继续烧录。
- “烧录当前固件”：使用哈希、版本和布局检查全部通过的缓存产物。
- “导出 HEX”：导出当前经过验证的固件，不接受外部 HEX 导入。
- “取消任务”：编译时终止对应进程树；烧录时取消挂起的 USB I/O 并关闭设备，不发送复位。

烧录步骤为 `info → unlock → erase → 128 字节分块写入 → reset`，硬超时为 90 秒。擦除开始后断线需要重新断电进入 ISP，再使用同一个已编译固件重试，无需重复编译。

## Android 端烧录（OTG）

Android 版在“编译与烧录”页使用与 Windows 相同的 USB-HID ISP 协议与流程（`pieblock_hid`），仅传输层替换为系统 `UsbManager`（USB Host）：

- 通过 OTG 转接线连接主控板；首次烧录会弹出系统 USB 权限确认。
- 应用直接访问 HID 接口的中断端点（`UsbRequest` 异步收发；Android 中断端点不支持同步 `bulkTransfer`），打开后常驻挂起中断 IN 请求，去掉 Windows/hidapi 语义的前导 `0x00` 报告 ID 后发送 64 字节报告；读输入报告超时返回空。
- 其余行为一致：只能冷启动进 ISP、烧录完成自动复位、再次烧录需重新断电上电；取消时关闭连接，可能需要重新上电。
- 设备无 USB Host 功能的机型不显示烧录区域（`android.hardware.usb.host` 为可选特性）。


## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 未检测到 ISP 主控板 | 关闭四个开关，拔掉 USB，等待断电后重新连接 |
| 检测到多块主控板 | 只保留需要烧录的一块，应用不会随机选择设备 |
| USB 设备被占用 | 关闭其他烧录工具，重新插拔主控板 |
| HEX 已变化或布局非法 | 重新点击“仅编译”，不要手工修改缓存文件 |
| Keil 目录无效 | 选择包含 UV4 和 C251 的 Keil 安装根目录 |
| Keil 许可证受限 | 使用应用许可证引导或 Keil License Management |
| 烧录成功后设备消失 | 正常复位行为；需要再次烧录时重新断电上电 |

## 发布构建

```powershell
cd apps\pieblock_app
C:\flutter\flutter\bin\flutter.bat pub get
C:\flutter\flutter\bin\flutter.bat analyze
C:\flutter\flutter\bin\flutter.bat test
C:\flutter\flutter\bin\flutter.bat build windows --release
```

发布整个 `build\windows\x64\runner\Release` 目录。应用依赖同目录的 `pieblock_hid.dll`、Flutter DLL、`data\flutter_assets` 和 `data\pieblock_runtime`。
