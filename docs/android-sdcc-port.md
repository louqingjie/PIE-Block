# PIE-Block Android SDCC 多进程移植

## 固定基线

- Flutter stable：3.47.1
- Android `minSdk`：24
- Android ABI：`arm64-v8a`、`x86_64`
- Android NDK：28.2.13676358
- SDCC fork：`912a589d4080c9cd5c5c1faf871c62dd5023580d`
- 原生 C ABI：5
- Coordinator AIDL 协议：2
- Worker AIDL 协议：1

原计划使用 NDK 27.3.13750724，但 Flutter 3.47.1 当前 Android 插件要求
28.2.13676358，因此应用与 FFI 包统一固定到 28.2。最低 API 与目标 ABI 不变。

## 运行架构

Flutter 主进程不加载 SDCC。一次构建由两个私有进程角色协作：

1. 非导出的前台 `SdccCompilerService` 运行在
   `:compiler_coordinator`，负责资源校验、构建计划、通知、实时日志、取消、
   产物校验和最终结果。
2. 非导出的 `SdccCompilerWorkerService` 运行在 `:compiler_worker`。
   每个 Worker 只执行一个翻译单元的“预处理 → MCS251 编译 → 汇编”，或只执行
   一次最终链接。
3. Coordinator 在每个阶段结束后先解除 `BIND_AUTO_CREATE`，再确认旧 Binder
   死亡。下一阶段必须取得新的 PID 与随机 nonce，避免 SDCC 全局状态跨翻译单元
   污染。
4. 全部 `.rel` 完成后，一个全新的链接 Worker 按清单顺序生成 HEX/MAP。
   Coordinator 再次检查 Intel HEX 校验和、FE/FF 地址、复位向量和 MAP 布局。

Coordinator 在完整构建期间保持同一 PID。Worker 连接、单阶段执行和退出均有
硬超时；取消、崩溃、Binder 断开或主进程退出不会产生可缓存固件。

## C ABI 5

C ABI 只暴露 `compileUnit` 与 `link` 两类请求：

- `compileUnit` 只接受一个源码、受控参数和一个目标 `.rel`，不得携带对象列表。
- `link` 只接受普通对象、库对象、受控链接参数及 HEX/MAP 目标，不得携带源码。

四个固定入口 `pb_cpp_main`、`pb_sdcc_main`、`pb_sdas251_main`、
`pb_sdld_main` 编入同一个 `.so`。embedded-host 仅允许 SDCC 驱动分派到内嵌
的 `sdcpp`、`sdas251` 和 `sdld`，拒绝未知工具、Shell 元字符和路径越界；
APK/AAB 中不存在这些工具的可执行文件。

中间对象使用与 Windows 后端一致的“源码名 + 稳定索引”命名，既避免同名碰撞，
也保证链接模块名可复现。成功后仅保留 HEX、MAP、统一日志和缓存元数据；
`.rel/.asm/.lst/.sym/.lk/.mem` 与阶段日志全部清理。

## 资源与构建指纹

Gradle 从固定固件目录打包 MCS251 头文件、运行库、构建清单和步兵/工程源码。
首次使用时逐文件验证 SHA-256，并原子部署到应用私有目录。临时文件写入私有
cache/support 目录，HEX 通过 Storage Access Framework 导出，无需通用存储权限。

Android 编译器指纹包含 SDCC 提交、ABI 5、Coordinator 协议 2、Worker 协议 1、
阶段对象哈希、原生库哈希、目标 ABI、资源包哈希、调度版本和源码规范化版本。
任一项变化都会使旧缓存失效。

## 安全门与验证状态

`pb_sdcc_is_available()` 只表示单阶段 Worker 具备执行能力。正式 Release 还必须
通过 Coordinator/Worker 协议、自检与黄金矩阵。Debug 构建用于真机验证；Release
当前仍未定义 `PB_SDCC_PIPELINE_ENABLED=1`，用户没有绕过入口。

ARM64 Android 16 真机已验证：

- 204 个只读资源逐文件校验与原子部署；
- 最小固件连续两次确定性构建；
- 步兵、工程完整源码集合均完成逐文件编译和链接；
- 每阶段 Worker PID/nonce 唯一，Flutter 与 Coordinator 不因 Worker 退出而变化；
- Worker 自动重绑定竞态已消除，连接/阶段/退出均有超时；
- 完整步兵构建实测约 46 秒，低于 120 秒门槛；
- 成功后中间文件清理，日志保留可见警告统计和 HEX SHA-256。

Release 安全门仍保持关闭，直到以下项目全部完成：

1. 对象命名对齐后的步兵、工程 Android HEX 与 Windows SDCC 黄金哈希一致；
2. 取消、并发拒绝、Worker 崩溃和 Binder 断开测试全部通过；
3. 当前 ARM64 真机完成重复构建，x86_64 模拟器完成完整构建；
4. 代表性 Android HEX 经 Windows USB-HID 烧录并完成硬件功能验证；
5. Release AAB、包内容、许可证和可复现构建检查通过。

## Android USB-HID 烧录（已实现，真机兼容性受限）

Android 端已接入与 Windows 相同的 STC32G USB-HID ISP 烧录协议（`pieblock_hid`）：

- 传输层：`UsbHidBridge.kt`（`UsbManager` + `UsbRequest` 异步收发中断端点；Android 规定中断端点不支持同步 `bulkTransfer`，同步路径真机写入返回成功但读永远无响应），通道 `cn.edu.cnu.pieblock/hid`；
- Dart 侧：`AndroidHidTransport` 复用现有 `HidFlasher`/`HidProtocol`，与 Windows 帧、块、ACK 完全一致；
- 已知差异：Android 中断端点发送 64 字节报告本体（去除 hidapi 前导 `0x00` 报告 ID）。

### 真机兼容性结论（2026-08-28 排查）

在 Redmi K80 Pro（HyperOS）与联想小新平板（ZUI）两台设备上均无法烧录：控制传输
（枚举、SET_IDLE）正常，但中断 OUT/IN 端点瞬间以 0 字节错误完成，且设备无
CLEAR_HALT/GET_REPORT 处理器，无恢复手段。

排查结论：STC32G ROM ISP 固件要求主机在**枚举后极短时间内（≈百毫秒级）建立
"claim + 报告描述符获取 + 常驻 IN 轮询"的内核驱动式会话**，之后才武装中断端点。
Windows（HIDCLASS 即时接管）与桌面 Linux（usbhid 同样即时）都满足；Android 的
USB 权限弹窗使 App 无法在窗口内完成会话建立（实测 ROM 每次重新插入都要求再次
授权），错过窗口后固件跳回用户程序（表现为蜂鸣器演奏旧乐曲）。已验证：

- 协议字节与 Windows 完全一致（full64 报告格式双端对照）；
- 时序复刻 Windows hidapi（打开只 claim、写完成才读）仍失败；
- WSL usbip 直通对照实验：同一板子在 Linux 内核 HID 驱动（usbhid）下 info
  交换完全正常，裸 usbfs（等价安卓路径）无论何种时序/EP0 预处理组合均复现
  「OUT 被 ACK 但固件不处理、IN 永久静默」。

结论属于设备固件对用户态 USB 主机的兼容性限制，非应用层代码缺陷。缓解措施：

- 应用已实现：attach 广播即时建会话、产品字符串人格校验（非 `USB-ISP` 时报
  「主控板正在运行用户程序」）、授权后重插重试流程；
- 若在个别机型（授权持久化、窗口更宽）上验证可行，欢迎按机型反馈；
- 通用可靠路径：安卓端编译后「导出 HEX」，用 Windows 端烧录。

## 验证命令

```powershell
# ARM64 最小、多进程取消与确定性测试
flutter test integration_test/android_sdcc_smoke_test.dart -d <device-id>

# 完整黄金矩阵；可用 dart-define 仅运行 infantry 或 engineer
flutter test integration_test/android_sdcc_full_build_test.dart `
  -d <device-id> --dart-define=PIEBLOCK_GOLDEN_KIND=infantry

# Windows 黄金构建
$env:PIEBLOCK_RUN_SDCC_GOLDEN = "1"
dart test packages/pieblock_toolchain/test/sdcc_windows_android_golden_test.dart

# Release 包内容审计
tools/verify_android_package.ps1 `
  -PackagePath build/app/outputs/bundle/release/app-release.aab
```

Android 发行代码使用 GPL-3.0-or-later。每个正式 APK/AAB 必须同时发布匹配的
SDCC fork 源码标签、许可证、第三方声明和可复现构建说明。
