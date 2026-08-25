# PIE-Block Android SDCC 移植基线

## 固定版本

- Flutter stable：3.47.1
- Android `minSdk`：24
- Android ABI：`arm64-v8a`、`x86_64`
- Android NDK：28.2.13676358
- SDCC fork：`912a589d4080c9cd5c5c1faf871c62dd5023580d`
- 原生 C ABI：3

原计划指定 NDK 27.3.13750724，但 Flutter 3.47.1 当前解析出的 Android
插件要求 NDK 28.2.13676358。应用和 FFI 插件统一提升到 28.2，避免由 Gradle
在不同模块选择两个 NDK。最低 Android API 和目标 ABI 不变。

## 发布边界

Android 包只允许包含 `libpieblock_sdcc_native.so` 和编译所需的只读资源，
不得包含或释放后执行 `sdcc`、`sdcpp`、`sdas251`、`sdld`。Keil 和 USB-HID
烧录仍只在 Windows 显示。

资源部署、编译缓存和临时目录分别使用应用 support/cache 目录，不申请通用
存储权限。HEX 通过 Android Storage Access Framework 导出。

C ABI 3 的请求显式携带源码列表、编译参数、链接参数以及 HEX/MAP/日志输出
位置；事件携带阶段、当前文件和进度，结果携带结构化错误码与错误/警告计数。
所有字符串和数组在启动时由原生层深拷贝，不引用 Dart 临时内存。

Gradle 在构建前从仓库的固定固件目录生成只读资源包，只收集 MCS251 头文件、
运行库、构建清单及步兵/工程所需源码。资源清单记录每个文件的 SHA-256；应用
首次编译前逐文件校验并通过临时目录原子部署。可使用
`tools/verify_android_package.ps1` 检查 APK/AAB 的 ABI、资源完整性和禁止文件。

## 已验证的 NDK 可行性

在隔离的临时源码和构建目录中，ARM64/API 24 与 x86_64/API 24 均已成功
生成对应架构的 ELF 样机：

| 阶段 | 临时产物 | 大小（字节） |
|---|---:|---:|
| C 预处理 | `sdcpp`（构建树中名为 `cpp`） | 2,040,696 |
| MCS-251 编译 | `sdcc` | 14,307,400 |
| MCS-251 汇编 | `sdas251` | 273,680 |
| ASxxxx 链接 | `sdld` | 434,936 |

x86_64 对应四个样机的大小依次为 1,950,584、13,897,736、258,808 和
412,928 字节。两套产物均已用 NDK `llvm-readelf` 核验目标架构。

进一步的 ARM64 库入口探针已验证：GCC `cc1 -E` 预处理入口可重链接为
2,581,496 字节的共享库并导出 `pb_cpp_main`；MCS251 编译入口可重链接为
15,311,800 字节的共享库并导出 `pb_sdcc_main`。这证明阶段代码可以进入
`.so`，但尚不证明错误退出和连续调用安全。

四阶段对象经过逐阶段全局符号命名空间隔离后，已能合并为单一 AArch64
共享库（18,711,200 字节），同时导出 `pb_cpp_main`、`pb_sdcc_main`、
`pb_sdas251_main`、`pb_sdld_main`。已验证的重链接过程位于
`tools/link_android_sdcc_probe.ps1`；它只生成可行性探针，不会把探针放入
APK/AAB。脚本还会输出不依赖 Android 可执行文件的可重定位阶段对象
`pieblock_sdcc_stages.o`，供后续 C ABI 适配层链接。

同一脚本已在 x86_64/API 24 基线上通过：共享库为 18,177,864 字节，阶段
对象为 31,035,584 字节；两个 ABI 均导出完整四入口。

当前 Android Release AAB 可成功构建（39.6 MB）。APK/AAB 都只包含
`arm64-v8a`、`x86_64` 两套 PIE-Block 原生库；构建后应执行：

```powershell
tools/verify_android_package.ps1 `
  -PackagePath apps/pieblock_app/build/app/outputs/bundle/release/app-release.aab
```

这些文件只是源码可移植性探针，不进入仓库和安装包。APK 检查目前仅有两个
目标 ABI 的 `libpieblock_sdcc_native.so`，未包含上述工具文件。

## 尚未解除的发布门槛

`sdcpp`、SDCC、ASxxxx 仍以进程入口、`exit()` 和进程级全局状态为生命周期
边界。把它们简单链接进 Flutter 进程会导致错误路径终止应用，连续构建也可能
污染状态。因此在完成以下项目之前，原生管线必须返回
`PB_SDCC_UNAVAILABLE`，且 `pb_sdcc_is_available()` 必须返回 0，不能生成或
缓存 HEX：

1. 四个入口改为显式上下文和返回码，错误路径不终止应用。
2. 移除 `system`、`popen` 和对子工具路径的查找，按阶段直接调用。
3. 日志、进度和取消统一接入 C ABI 事件队列。
4. 同一进程连续构建 100 次，并通过异常输入与内存增长测试。
5. ARM64 真机和 x86_64 模拟器产物与 Windows 黄金 HEX 字节级一致。

这是一项安全门槛，不允许用“能交叉编译出 Android 可执行文件”替代真正的
库级可重入移植。
