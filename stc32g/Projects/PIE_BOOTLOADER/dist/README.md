# PIE_BOOTLOADER 出厂烧录说明

这个目录里的 `pie_bootloader.hex` 是**分发套件的一部分**，不是普通编译产物。
每块主控板出厂前需要手工烧一次，之后用户的程序就能全程走串口 OTA 升级，
再也不用碰 STC-ISP。

## 烧录步骤

用**官方 STC-ISP 软件**，不要用 stcgal（它的 `program_eeprom_split` 处理有 bug，
设过之后固件不启动）。

| 项目 | 值 |
|---|---|
| 单片机型号 | STC32G12K128 |
| 输入用户程序运行时的 IRC 频率 | **33.1776 MHz** |
| EEPROM 大小 | **128K** |
| 程序文件 | `pie_bootloader.hex` |

后两项最容易漏，两个都漏不了：

- **频率必须是 33.1776MHz**。bootloader 的波特率是按这个主频算的
  （`BAUD = 65536 - FOSC/4/115200`），频率不对串口就通不了。
  **波特率为 115200**（蓝牙 SPP 稳定上限），与 App 烧录模式、上位机统一。
- **EEPROM 必须设 128K**，否则 IAP 操作全部返回 `CMD_FAIL`，无法擦写。
- **烧完必须断电重新上电**，EEPROM 大小的设置只有重新上电才生效。
  官方文档专门标注了"重要，容易被忽略"。只按复位键没用。

## 验证烧录成功

```
python ../../../toolchain/stcflash/bootloader_probe.py COM11 connect
```

期望输出 `status=OK`、`payload=02 00`（版本号 0x0200）。

此时板上还没有用户程序，bootloader 会因为"App 首字节不是 LJMP"而停在下载模式，
这是正常的。

## 逃生通道

**P32 拉低再上电**，bootloader 会无条件停在下载模式，不去跳转 App。
用户程序跑飞、串口被占死的时候靠这个救回来。

## 别改这个目录里的 hex

它必须与 `../MDK/Objects/pie_bootloader.hex` 一致。重新编译 bootloader 后
记得同步拷过来，否则出厂烧的和代码就对不上了。
