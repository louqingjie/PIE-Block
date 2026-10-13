# SDCC（MCS251）组帧时低字节被写成高字节

一次实机通信故障的记录：同一份固件源码，Keil 编译能正常和拓展板通信，SDCC 编译不能。

## 现象

- 主控板 UART1（P30/P31，230400 8N1）向拓展板发 21 字节命令帧。
- 用 USB 转串口接 P31 抓包对比两个编译器产物（帧头 `AB BC`、帧尾 `CD DE`、长度 21
  都对齐，说明波特率/接线没问题），**载荷里每个 16 位字的两个字节完全相同**：

  | 意图 | Keil 抓包 | SDCC 抓包 |
  | --- | --- | --- |
  | Init 频率 50Hz | `00 32` | `00 00` |
  | Init 频率 10000Hz | `27 10` | `27 27` |
  | Duty 5000 | `13 88` | `13 13` |
  | Duty 500 | `01 F4` | `01 01` |
  | Duty 512 | `02 00` | `02 02` |

- 结果：拓展板收到的是频率 `0x2727`（10023Hz）、占空比 `0x0101`（257）这类错值，
  摩擦轮电调在错的启动信号下完全不动 —— 表现为「Keil 通、SDCC 不通」。

## 根因

出问题的写法是「`uint16_t` 数组 + `3+i*2` / `4+i*2` 变址」逐字节落帧：

```c
uint16_t values[8];
values[0] = p60; values[1] = p62; values[2] = p64; values[3] = p66;
values[4] = p74; values[5] = p75; values[6] = p76; values[7] = p77;
for (i = 0; i < 8; i++) {
    control_frame_pack[3 + i * 2] = (uint8_t)(values[i] >> 8);
    control_frame_pack[4 + i * 2] = (uint8_t)(values[i] & 0xff);
}
```

SDCC（实测 4.6.0，`-mmcs251 --model-large --stack-auto --opt-code-size`）在第二处
（低字节）只取了元素的首字节 —— 大端存储下就是高字节，于是高字节被写进两个字节位置。

两个佐证：

- 编译时 SDCC 会刷 `DPTR no-match: cached=(#_control_frame_pack,0x0) new=(#(_control_frame_pack,0x0)`
  警告，指向的就是它自己的 DPTR 缓存优化，可当作信号。
- 把该函数单独编成汇编（`sdcc -S`）后可见 `control_frame_pack[4 + i*2]` 那一段只有一次
  `mov a,@dpx`，落在元素首字节，没有 `inc dpx` 去取低字节。

对照参考固件 `stc32g_sdcc/projects/*` 与《RM电控指南》里的实现：它们本来就是逐字展开的写法，
所以 Keil 编译的参考工程一直是好的 —— 正好解释「Keil 通、SDCC 不通」。

## 修复

改成逐字展开，直接从形参取高/低字节（与《RM电控指南》参考实现一致）：

```c
control_frame_pack[3] = (uint8_t)((p60 >> 8) & 0xFF);
control_frame_pack[4] = (uint8_t)(p60 & 0xFF);
control_frame_pack[5] = (uint8_t)((p62 >> 8) & 0xFF);
control_frame_pack[6] = (uint8_t)(p62 & 0xFF);
/* ... 共 8 组，模板见 code_generator.dart 的 ExpansionBoradControl ... */
```

- 改了代码生成器里步兵/工程共用的那份、以及调试工程模板那份 `ExpansionBoradControl`；
  调试工程的 `FrictionSendDuty` 也按脚展开，不再用 `values[slot]`。
- 提交：`c4e91d7`（`fix(firmware): 修复 SDCC 下拓展板组帧把低字节写成高字节`）。
- **实机验证通过**：重新生成并烧写后抓包恢复成 `27 10`、`01 F4` 等正确配对，拓展板通信正常。

## 规避要点

- SDCC（MCS251）下打包字节时，避免「`uint16_t` 数组 + 变量/表达式变址 + `>> 8` / `& 0xff`」
  的组合；直接从形参或标量局部变量取高/低字节。
- 需要按运行时下标选通道时用 `switch` 展开（例如调试工程的 `FrictionSendDuty`），
  不要用 `values[slot]`。
- 相邻的已知坑（见《RM电控指南》）：不要把栈上的帧数组当整帧指针传给别的函数，
  SDCC 的通用指针取数同样会生成错误字节。
- 自检手段：改完生成固件后用随包 SDCC 编一次 `.asm`，看一眼落帧指令取的是不是不同字节；
  上机则 230400 8N1 抓 P31，核对每个 16 位字的高/低字节。
