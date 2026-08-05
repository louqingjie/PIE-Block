#ifndef __DFU_H__
#define __DFU_H__

/* 强制下载引脚：上电时拉低则无条件停在下载模式，是 App 跑飞后的硬件逃生通道。
   官方例程用 P33，我们改 P32 —— P33 在本项目里是蜂鸣器。
   串口 UART1 已切到 P43/P44（见 main.c 的 sys_init）。
   P3 口占用情况：P32 强制下载、P33 蜂鸣器、P34 遥控器复位、P37 状态灯。
   改这个引脚要同步改 dfu.c 里 P3M1/P3PU 操作的位掩码（当前是 0x04 = P32）。 */
#define DFU_FORCEPIN            P32
/* DFU_FORCEPIN 对应的位掩码，dfu.c 配置上拉输入时用 */
#define DFU_FORCEPIN_MASK       0x04

#define DFU_TAG                 0x12abcd34

#define DFU_CMD_CONNECT         0xa0
#define DFU_CMD_READ            0xa1
#define DFU_CMD_PROGRAM         0xa2
#define DFU_CMD_ERASE           0xa3
#define DFU_CMD_REBOOT          0xa4

#define STATUS_OK               0x00
#define STATUS_ERRORCMD         0x01
#define STATUS_OUTOFRANGE       0x02
#define STATUS_PROGRAMERR       0x03
#define STATUS_ERRORWRAP        0xff

void dfu_check();
void dfu_events();

extern DWORD xdata DfuFlag;

#endif
