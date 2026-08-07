# btctl —— 经典蓝牙 (SPP) 扫描 / 配对伴生工具

给 Godot 上位机用的「经典蓝牙串口（HC-05/HC-06 这类 SPP 模块）」扫描/配对工具。
已实现 `--scan` 与 `--pair`。

## 为什么存在

- Godot（GDScript 与 C#）没有内置蓝牙 API，蓝牙是操作系统能力，必须桥接系统层。
- 应用要「无线烧录」，但 HC-05/06 必须先与 Windows 配对成虚拟串口
  （"标准串行over蓝牙链接 COMx"）才能走现有 Python stcflash 链路。
- 现在这一步要学生去系统设置里手动配对；btctl 的目标是将来在应用内
  完成「查找 → 配对」。
- 扫描走 Win32 `bluetoothapis.dll` 的**真实查询**（`fIssueInquiry`），与
  Windows「设置 → 蓝牙 → 添加设备」同一套机制，不会漏掉配对模式里的模块。
  WinRT AEP 在无设备时可能秒返回空，不可靠（实测 198ms 返回空）。
- 适配器开关状态走 WinRT `Radio`；后续配对走 WinRT `DevicePairing`（按 MAC）。

## 构建

需要 .NET SDK 8（开发机已装 8.0.423）。

```powershell
# 框架依赖单文件（目标机需装 .NET 8 运行时；开发机即可）
powershell -ExecutionPolicy Bypass -File tools/btctl/build.ps1
# 自包含单文件（学生机免装 .NET，体积 ~70MB；给应用打包用这个）
powershell -ExecutionPolicy Bypass -File tools/btctl/build.ps1 -SelfContained
```

产物：`tools/btctl/out/btctl.exe`。`bin/ obj/ out/` 已在 `.gitignore` 忽略，
仓库只提交源码（`Program.cs` / `btctl.csproj` / `build.ps1`）。

## 用法

```
btctl --scan [--multiplier <1..48>] [--verbose] [--out <json文件>]
btctl --pair <MAC> [--pin <pin>] [--system-dialog] [--enable-spp] [--verbose] [--out <json文件>]
```

- `--scan`：输出 JSON：适配器、可发现设备（真实查询）、已配对设备。
- `--multiplier`：查询时长倍数，每倍约 1.28s，默认 8（≈10s）。测试可调小（2≈2.6s）。
- `--pair <MAC>`：与指定地址配对。先尝试 `--pin` 的静默配对（HC-05/06 固定 1234）；
  失败自动回退到系统配对对话框（用户手动输 PIN / 点完成）。加 `--system-dialog` 直接走对话框。
- `--enable-spp`：配对成功后启用 SPP 串口服务（让 "标准串行over蓝牙链接" 虚拟串口出现）。
- `--verbose`：附加异常堆栈等诊断信息。
- `--out`：把 JSON 额外写入指定文件（UTF-8）。Godot 侧读文件而非解析 stdout，
  避免中文 Windows 下 `OS.execute` 输出按系统代码页乱码。

退出码：0=成功 1=运行时错误 2=用法错误。

`--pair` 输出：

```json
{
  "ok": true,
  "paired": true,
  "method": "pin",            // pin=静默PIN / dialog=系统对话框 / pin_fallback_dialog=静默失败后回退
  "mac": "00:1B:10:XX:XX:XX",
  "enable_spp": true,
  "pair_ms": 800
}
```

### 输出示例

```json
{
  "ok": true,
  "scan": {
    "radio_ready": true,
    "radios": [ { "Name": "蓝牙", "State": "on" } ],
    "discoverable": [ { "Name": "HC-06", "Address": "00:1B:10:XX:XX:XX", "Paired": false, "Connected": false } ],
    "paired": [],
    "discovery_ms": 10421
  }
}
```

字段说明：

- `radio_ready`：是否有处于开启状态的蓝牙适配器。`false` 时应用应提示去系统开蓝牙。
- `radios[].State`：`on` / `off` / `disabled` / `error`。
- `discoverable`：附近可发现的设备（可能含已配对/已连接的，用 `Paired`/`Connected` 区分）。
- `paired`：Windows 记住的已配对设备（缓存，不再查询）。
- RSSI：Win32 查询不提供信号强度，本阶段不输出该字段。

## Godot 集成

- `scripts/bt_scan.gd`：`BtScan` 类（btctl 封装，扫描 + 配对）。
  - `find_exe()`：定位 exe，优先 `user://btctl/btctl.exe`（应用部署），其次
    `res://tools/btctl/out/btctl.exe`（开发机）。
  - `run_scan(multiplier)` / `run_pair(address, pin, system_dialog, enable_spp)`：同步阻塞，
    返回 `{"ok", "exit", "data"}`，供无头测试/命令行。
  - `scan_async(...)` / `pair_async(...)`：后台线程跑，完成发 `finished(result)`，失败发 `failed(msg)`。
    扫描约 10s，**别在主线程直接调同步版**（会卡 UI）。
- `scenes/bt_pair.tscn` + `scripts/bt_pair.gd`：`BtPairPanel` 配对引导面板
  （扫描→选择→配对→等待虚拟串口→重试烧录）。
- `ui.gd`：顶栏「蓝牙」按钮可手动打开；烧录失败且属于「连不上板子」类
  （stage 为 port/connect/env/空）时自动弹出引导。配对成功检测到虚拟串口后可点「重试烧录」。
- 无头测试：`scripts/test_bt_scan.gd`、`scripts/test_bt_pair.gd`（后者纯逻辑 + 管道，无需真机）。

## 平台 / 硬件限制

- 仅 Windows；需经典蓝牙（BR/EDR）适配器与 `bthserv` 服务。
- HC-05/HC-06 是经典 SPP，**不是 BLE**；本工具只做经典蓝牙，BLE 那套不管用。
- 首次配对后 Windows 记住设备；发现需要模块处于可发现状态（HC-06 常开、
  HC-05 按住按钮进配对模式）。
- **PIN 的真相**：Windows 对经典蓝牙没有官方「应用静默注入 PIN」的保证路径。
  本工具先试 `BluetoothAuthenticateDevice` 带 PIN 的静默配对，失败再弹系统对话框。
  HC-06 固定 1234；HC-05 可用 AT 命令改。**静默 PIN 是否稳定需真机验证**——
  若不行，对话框方案始终可用（应用内已提示默认 PIN 1234）。
- 本机实测：真实查询稳定 ~10.4s（multiplier 8）；首次执行（尤其刚编译后）
  可能被 Defender/SmartScreen 拖慢，属一次性开销。

## 已知坑（实现备忘）

- `BluetoothFindFirstRadio` 的**返回值是搜索句柄**（`BluetoothFindRadioClose` 关它），
  **出参才是电台句柄**（`BluetoothAuthenticateDevice`/`SetServiceState` 用它）。
  两者混淆会导致 AccessViolation。
- 配对后 SPP 虚拟串口有延迟，Godot 面板按 1s 轮询最多 20s。
