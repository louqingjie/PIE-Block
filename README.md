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
- 只读 C 代码预览、搜索、复制和导出 `main.c`；音乐项目试点可直接生成等价汇编并导出 `main.asm`（详见 `docs/汇编生成器.md`）
- 随应用发布的离线 SDCC C251，以及可选的本地 Keil C251 全量构建
- HEX 地址与校验和检查、按内容哈希复用构建结果、导出 HEX
- STC32G ROM USB-HID 主控板烧录、进度、取消和失败提示

暂不提供云端编译、串口/蓝牙烧录、AI 编辑、3D 仿真、CLI 或 MCP。官网嵌了一个 Web 版（只读暗色、默认打开），可以配置项目、看生成的 C 代码，编译与烧录仍然只能在桌面版完成——浏览器里既没有本地工具链也访问不到 USB-HID。Web 版的项目存在浏览器 localStorage 里，导入导出走文件上传下载。Android 可配置、编辑、预览和编译音乐项目；步兵/工程离线 SDCC 正在进行多进程真机黄金验证，Release 安全门通过前不对用户开放，且 Android 仍不支持 USB-HID 烧录。

## 项目结构

```text
./                       Flutter 应用（pubspec.yaml 位于仓库根目录）
packages/pieblock_core/  纯 Dart 项目模型、校验器与 C/汇编生成器
packages/pieblock_toolchain/ Dart SDCC/Keil 构建、HEX 校验与产物缓存
packages/pieblock_hid/   Dart 烧录协议与 Windows 原生 HID 传输
packages/pieblock_sdcc_native/ Android C ABI 5 与多进程编译桥接
stc32g/                  STC32G 固件和硬件参考代码
stc32g_sdcc/             SDCC C251 支持库与离线测试
keil_server/             独立云编译服务（不由当前应用调用）
docs/                    硬件与项目格式文档
```

Flutter UI 不包含生成规则。`pieblock_core` 是配置、检查和代码生成的唯一实现（C 与汇编两种输出目标均在此实现）。

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

Linux 构建与打包（x64）：

```bash
tools/prepare_sdcc_toolchain.sh   # 从 sdcc-c251 子模块编译并暂存内置 SDCC 工具链
flutter build linux --release     # CMake 会把工具链与固件模板装进 bundle
tools/package_flutter_linux.sh    # 校验并打包 build/dist/PIEBlock-<版本>-linux-x64.tar.gz
```

`flutter build linux --release` 直接产出自包含 bundle（`build/linux/x64/release/bundle/`），`data/pieblock_runtime` 由 `linux/CMakeLists.txt` 在构建时安装，发布时保留整个目录；Linux 端仅支持 SDCC 离线编译，USB-HID 烧录目前仅 Windows 可用。

编译与主控板接线、开关位置和故障排查见 [Flutter 编译与烧录指南](docs/Flutter编译与烧录指南.md)。
Android 离线 SDCC 的架构、安全门和验收状态见 [Android SDCC 多进程移植](docs/android-sdcc-port.md)。

## 官网与在线体验

官网是 `website/` 下的零依赖静态站（`wrangler.jsonc` 把整个目录交给 Cloudflare
Workers 托管）。英雄区右列就是 Flutter Web 版：页面加载完之后才拉取应用，应用画出第一帧会
`postMessage` 通知页面淡入，10 秒内没就绪就换成一句提示加一个重试按钮。

应用右上角有个全屏按钮：优先原地全屏（`requestFullscreen`，填到一半的配置不会
丢，Esc 就回到页面）；iOS Safari 不给非视频元素全屏，那种情况下按钮退化成在新
标签页打开独立的 `/app/` ——那个页面本来就在，iframe 加载的就是它。

发布：

```bash
tools/build_website.sh      # Windows: tools\build_website.ps1
wrangler deploy
```

构建脚本做三件事：`flutter build web --base-href /app/ --pwa-strategy=none`、
把产物拷进 `website/app/`、删掉不会被下载的 `*.symbols`。产物约 38MB 且**不进 git**
（`.gitignore` 已忽略 `website/app/`），所以每次改完代码要重新跑一遍脚本再部署。

### 工作流区的界面截图

`#flow` 区那 4 张图是**真实应用截图**，不是画的：`website/assets/shots/*.webp`，
每张 1440×902、约 40KB。界面改了以后重拍的办法：

1. 起本地服务：`python3 -m http.server 8765 -d website`
2. 把 `website/assets/shots/demo/<名字>.json` 灌进浏览器的 localStorage：
   键 `pieblock.project:<项目名>.pieproj` 放该 JSON，键 `pieblock.settings` 放
   `{"theme":"dark","recent":["<项目名>.pieproj"],"compiler":"sdcc"}`
3. 打开 `/app/`，在首页点开那个项目——它就落在 JSON 里
   `guide_progress.current_step_id` 指定的那一步
4. 窗口设到 1740×1090（页面会报 1438×901），整屏截图
5. 转格式：`magick in.png -resize 1440x -quality 82 out.webp`

四份演示项目与图片一一对应：`wizard` 向导「遥控器与底盘」、`review` 检查与摘要、
`code` 生成代码、`music` 钢琴卷帘。**`review` 那份是故意带错的**（引脚冲突、
摩擦轮占空比不是整百值、死区超建议值），问题列表才有内容——四份 JSON 由
`packages/pieblock_core` 的模型构造，改完模型可以照着重生成。

「编译与烧录」没有真图：Web 版的这一步是「请用桌面版」引导页，而桌面端的烧录
进行中状态需要插着真实主控板才出现。所以第三块的配图是生成代码页，文案也相应
改成了讲代码生成，编译烧录缩成一条「在桌面版完成」。

`--pwa-strategy=none` 是刻意的：Flutter 默认的 service worker 缓存很激进，网页版
迭代时用户容易卡在旧版本。`--base-href /app/` 也是必需的：Cloudflare 只能托管一个
目录，应用必须能识别自己在子路径下，否则会去根路径找 `main.dart.js`。

Web 版与桌面版共用同一套代码，差异都由 `lib/src/platform/` 下的条件导入隔离
（设置存 localStorage 还是 settings.json、项目存浏览器还是文件、导出走下载还是路径
对话框、有没有本地 Keil 与编译器）。`deploy_controller` 在 Web 上是空桩，这也顺带
把两个 `dart:ffi` 包挡在 Web 构建之外。

## 持续集成

`.github/workflows/windows.yml` 在 push / PR 到 `main` 以及手动触发时校验 Windows 构建，分两段执行：

1. **静态分析与单元测试**（ubuntu，约 2 分钟）：`pieblock_core`、`pieblock_hid`、`pieblock_toolchain` 三个包分别 `dart analyze` + `dart test`，再跑根目录的 `flutter analyze` + `flutter test`。
2. **Windows 构建与打包**（windows-latest，首次 20–35 分钟，工具链缓存命中后 5–8 分钟）：在 MSYS2 UCRT64 里跑 `tools/build_sdcc_windows_package.sh` 编译 Windows 版内置 SDCC 工具链（按 `sdcc-c251` 子模块提交与脚本哈希缓存），再用 `tools/prepare_sdcc_toolchain.ps1 -PackageOnly` 暂存并生成 `bundle_manifest.json`；随后校验平台字段，跑 `PIEBLOCK_RUN_SDCC_GOLDEN=1` 的 SDCC 金样比对，再 `flutter build windows --release` 并用 `tools/package_flutter_windows.ps1 -SkipBuild` 出安装包。

产物保留 14 天，名称为 `PIEBlock-<版本>-windows-setup.exe`（Inno 安装包）与 `PIEBlock-<版本>-windows-x64-release.zip`（免安装 `Release` 目录）。金样校验可用 `workflow_dispatch` 的 `skip_golden` 输入临时跳过。

推送 `v*` 标签会额外触发 `release` job：校验标签与 `pubspec.yaml` 版本一致后，用该版本的产物创建 GitHub Release。Release 正文优先取 `docs/releases/<版本>.md`，没有该文件时用自动生成的变更说明——发版请同时提交版本说明文件。

本地复现 CI 的检查：

```powershell
git submodule update --init sdcc-c251
.\tools\prepare_sdcc_toolchain.ps1 -Force   # 需要 MSYS2 UCRT64 的 bison/flex/make、toolchain 与 boost/zlib
$env:PIEBLOCK_RUN_SDCC_GOLDEN = '1'
Push-Location packages\pieblock_toolchain; dart test; Pop-Location
.\tools\package_flutter_windows.ps1
```

## 项目文件

新版继续使用 `.pieproj` 扩展名，但只接受 `format_version: 15`。格式 14 和旧 Godot 格式不会自动转换，需在新版中重新创建配置。新项目不预填任何必填配置；步兵云台轴默认各有一个未填执行器，可增删为多个或留空；调试工程预置十路停用引脚和 3 秒安全时长。音乐工程默认 480 PPQ、120 BPM 和 4/4 拍，可重新导入原始 MIDI。详细结构见 [项目文件格式](docs/Flutter项目文件格式.md)。
