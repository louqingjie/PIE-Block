# STC32G USB-HID ISP 烧录协议

> 本文档记录对 STC32G ROM bootloader（「USB-ISP」HID 设备）烧录协议的完整逆向
> 结果。全部经真机验证（2026-08-07）：`pie_block_hid.py` 用它成功烧录完整 TEST
> 固件并复位运行。

## 1. 设备识别

- VID `0x34BF`（STC）/ PID `0x1001`（ROM bootloader 「USB-ISP」）
- 标准 HID 设备，**免驱动**；报告描述符：INPUT/OUTPUT 各 64 字节、无 report ID
- 进入 ISP 模式：**只能上电冷启动**（HID 不支持复位脚进入）；烧录后复位进 App，
  再烧需重新上电
- 设备打开后**不主动推包**，需发命令才有响应

## 2. 帧格式（主机 ↔ 设备）

```
主机→设备: 46 B9 6A <len_hi> <len_lo> <payload...> <csum_hi> <csum_lo> 16
设备→主机: 46 B9 68 <len_hi> <len_lo> <payload...> <csum_hi> <csum_lo> 16
```

- `len` = 从方向字节（6A/68）到帧尾（16）的字节数（含方向、长度、payload、
  校验、16）
- `csum` = payload 之前所有字节（方向+长度+payload）的 16 位和，`sum & 0xFFFF`，
  大端
- HID 传输：每报告前加 `0x00` report-id，**大帧拆成多个 64 字节报告发送**，
  设备按长度字段跨报告重组（实测：141 字节写帧拆 64/64/13 三个报告）
- **主机必须按设备可持续的速率推帧（报告之间要留间隔）**：设备每收一帧就编程
  128 字节 flash，推帧速率高于它的编程速率时会先丢帧、随后整块卡死（设备不下总线、
  不复位，但再也不回包，只能断电重新上电）。同一块板子、同一份 414 块固件实测：
  报告间隔 1ms（≈91 块/秒）→ 第 130 块卡死；20ms（≈20 块/秒）→ 414 块全部写完 +
  复位，21.4 秒。Linux 传输层默认 20ms/报告，Windows 侧 1ms 够用（`WriteFile` 自带
  驱动往返延迟）。Dart 移植一度把间隔删成 0，表现为首块 0x0000 正常、第二块 0x0080
  就完全没有响应（详见
  [docs/pitfall/HID烧录写块无响应.md](../../../docs/pitfall/HID烧录写块无响应.md)）
- **写一份报告≠设备已收到**：Linux hidraw 的写是异步的，设备忙时 `::write` 返回
  `-EBUSY` 且报告不会发出，写侧必须像 Windows 的 `WaitForSingleObject` 那样对忙错误
  做有界退让重试（见 `packages/pieblock_hid/src/pieblock_hid_hidraw.cpp`）
- **不要在烧录中途关闭 hidraw 句柄**：该固件要求主机保持常驻 IN 轮询会话，实测关闭
  并重开会立刻失联
- 卡死后断点续烧：闪存内容非易失，断电重新上电进 ISP 后用 `--no-erase --start-block N`
  继续写剩余块即可，不需要重新擦除

## 3. 命令表

| 命令 | payload | 响应 | 说明 |
| --- | --- | --- | --- |
| start | `00 00` | 56B 状态包 | 含模型 magic、BSL 版本、UID、时钟等（AiCube-ISP 首帧） |
| info | `01 00 00 00 00 00 00 80 00` | `01 00 70` | 状态确认 |
| unlock | `05 00 00 5a a5` | `05 00 74` | 解锁 |
| erase | `03 00 00 5a a5` | `03 <UID 7B> <2B>` | 擦除；UID 在 payload 第 1-7 字节 |
| 写用户区首块 | `32 <addr_hi> <addr_lo> 5a a5 <128B>` | `02 54` | 写 flash 首块（0xFE0000 段） |
| 写用户区后续 | `12 <addr_hi> <addr_lo> 5a a5 <128B>` | `02 54` | 写 flash 后续块（0xFE0000 段） |
| 写 0xFF0000 区 | `02 <addr_hi> <addr_lo> 5a a5 <128B>` | `02 54` | 写 0xFF0000 段（中断向量/关键数据） |
| set options | `04 00 00 5a a5 <选项47B>` | `04 54` | 选项设置（含状态包回读数据） |
| reset | `ff` | 无响应 | 复位运行新固件 |

写成功响应 payload 以 `02 54` 开头（stcgal 同款成功标志）；options 成功响应
`04 54`。

## 4. 地址映射（关键！）

**STC32G 有两种写地址基准：**

```
写用户代码区（cmd 0x32/0x12）：ISP 地址 = hex地址 - 0xFE0000    （hex地址 0xFE0000-0xFEFFFF）
写 0xFF0000 区（cmd 0x02）：   ISP 地址 = hex地址 - 0xFF0000    （hex地址 0xFF0000+）
0x0000 基址的 hex（如 pie_bootloader.hex）直接用原地址
```

- TEST hex 用户代码 0xFE0000-0xFE6096（~26KB）→ cmd 0x12 写 ISP 0x0000-0x6080
- TEST hex 0xFF0000 段（5 个 128B 块：0x0000/0x1000/0x1080/0x1100/0x1300）→
  cmd 0x02 写
- **0xFF0000 段必须写！跳过会导致固件不运行**（该段含中断向量/关键配置）
- 每块 128 字节，地址每块 +0x80

## 5. 完整烧录流程（字节级模仿 AiCube-ISP）

```
start(00 00) → 56B 状态包 → info → unlock → erase
→ 写用户区（首块 0x32，后续 0x12，地址 = hex-0xFE0000）
→ 写 0xFF0000 区（cmd 0x02，地址 = hex-0xFF0000）
→ set options（cmd 0x04，payload 含状态包回读的配置字节）
→ reset（cmd 0xff）
```

## 6. 工具

- `pie_block_hid.py`：主烧录器。`python pie_block_hid.py <hex> [--no-reset]`
- `linux_hidraw_flash.py`：Linux 免依赖（hidraw + ioctl，不需要 hidapi）烧录器，
  支持 `--probe-only` 探活、`--dry-run` 打印计划（与
  `packages/pieblock_hid/tool/dump_block_plan.dart` 逐行对拍）、`--report-gap-ms`
  调报告间隔、`--no-erase --start-block N` 断点续烧
- `enumerate_hid.py`：枚举确认设备
- `probe_hid.py` / `seq_hid.py` / `write_hid.py`：协议探测
- `analyze_capture.py`：解析 USBPcap 抓包提取 STC 帧
- `capture_usb.ps1` / `install_usbpcap.ps1`：抓包与驱动安装
- `hid_loader.py`：Windows 下加载 hidapi.dll（需放 `.venv\Scripts\hidapi.dll`）

## 7. 备注

- hidapi 的 `write` 超过 64 字节会**静默截断**，不能用于大帧；必须多报告分片
- 设备对格式错误的命令敏感：错误写命令可能使其复位进 App（从 USB 消失），
  需重新上电
- 响应 `02 54` 是写成功；`00 00` 命令可拿完整状态包（含 magic `f7e3` =
  STC32G12K128）
