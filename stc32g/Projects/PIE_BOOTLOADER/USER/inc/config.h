#ifndef __CONFIG_H__
#define __CONFIG_H__

/* pie-block bootloader 配置。
   本工程源自 STC 官方例程 STC-official-user-UART-ISP-bootloader-demo，
   除本文件与 dfu.h 的引脚定义外，其余源码保持原样，勿随意改动。 */

/* 主频。官方例程是 24000000UL，我们的板子跑 33.1776MHz
   （与 stc32g/Libraries/startup/inc/common.h 的 FOSC 一致）。
   烧录 bootloader 时 STC-ISP 里的工作频率也必须选 33.1776MHz。 */
#define FOSC                    33177600UL

/* 波特率装载值。表达式随 FOSC 自动跟，不要手改成常量。
   33177600/4/115200 = 72 整，实际波特率误差 0%。 */
#define BAUD                    (65536 - FOSC / 4 / 115200)

/* 启用 READ 命令。原例程默认关掉它，但没有 READ 就无法在下载后读回校验，
   只能靠"PROGRAM 没报错"来推断，那不足以证明写对了。
   代价是几十字节代码，4K 里放得下。 */
#define DEBUG

/* bootloader 占用的 flash 大小（物理 0xFF0000 起），App 从 0xFF0000+LDR_SIZE 开始。
   改这个值必须三处同步：
     1. 本文件
     2. USER/src/isr.asm 的 `LDR_SIZE EQU`
     3. 所有 App 项目 uvproj 的 INTVECTOR(...) */
#define LDR_SIZE                0x1000
#define LDR_VERSION             0x0100

#endif
