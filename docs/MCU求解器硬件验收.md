# MCU 求解器硬件验收

本验收用于确认工程 3D 仿真烧录的无执行器 IO 固件能够通过 USB 和蓝牙稳定执行机械臂求解协议。

## 安全准备

1. 断开执行器电源。仿真固件本身不初始化 PWM 或扩展板输出，但首次验收仍不得带动力执行器。
2. 确认连接的是主控板 UART1；扩展板不能烧录程序。
3. 在工程 3D 页面点击“编译并烧录求解器”，等待 HELLO、协议版本和构型指纹全部匹配。
4. 记下状态区显示的 16 位求解器指纹，并关闭 3D 页面以释放串口。

## 自动协议验收

USB 示例：

```powershell
godot --headless --path . --script scripts/dev_ik_sim_hardware_acceptance.gd -- `
  --port=COM11 --link=usb_serial --samples=1000 `
  --fingerprint=0011223344556677 `
  --report=user://ik_sim_hardware_acceptance_usb.json
```

蓝牙示例：

```powershell
godot --headless --path . --script scripts/dev_ik_sim_hardware_acceptance.gd -- `
  --port=COM5 --link=bluetooth --samples=1000 `
  --fingerprint=0011223344556677 `
  --report=user://ik_sim_hardware_acceptance_bluetooth.json
```

脚本使用产品中的同一 `IkSimLink`，依次执行：

- `HELLO`
- 连续 `PING`
- 保持当前末端位姿的 `STEP_POSE`
- 保持当前关节角的 `SET_JOINTS`
- `HOME`

报告记录固件类型、协议/算法版本、指纹、构形诊断、RTT 最小/平均/最大值、CRC 错误、旧序号丢弃和超时次数。验收要求：

- `ok = true`
- `firmware_type = 1`
- `protocol_version = 1`
- `algorithm_version = 2`
- `fingerprint` 与当前 3D 构型一致
- `crc_errors = 0`
- `dropped_sequences = 0`
- `timeouts = 0`

蓝牙链路不要求单次 RTT 小于 10ms；要求目标采样不积压旧请求，持续运行不掉线。

## 无输出检查

自动协议验收分别执行两次：

1. 扩展板断开。
2. 扩展板连接，但执行器电源保持断开；用示波器或逻辑分析仪观察扩展板控制链路和主控板 MP03/MP74。

两种情况下均不得出现 PWM 初始化、PWM 更新或 `ExpansionBoradControl` 控制帧。完成后再接执行器电源，确认仿真固件不会驱动电机或舵机。

## Bootloader 版本

新版常驻 bootloader、应用固件和仿真通信均使用 UART1 `230400`。如果工具检测到旧 `115200` bootloader，必须先使用官方 STC-ISP 对主控板进行一次物理升级；旧版本不参与蓝牙一键烧录验收。

## 恢复正式固件

退出 3D 页面不会自动恢复正式程序。验收完成后必须在工程页明确烧录正式工程代码，并确认“主控板当前为仿真固件”的警告消失。
