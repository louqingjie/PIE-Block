#ifndef STC32G_SDCC_MUSIC_CLOCK_H
#define STC32G_SDCC_MUSIC_CLOCK_H

#include <stdint.h>

/*
 * 音乐固件的毫秒级时间基准：Timer0 16-bit 自由计数（12T），主循环按
 * "两次读取之间的 16-bit 差值" 累积 ticks。
 *
 * 不启用定时器中断，也就不会在中断里碰 DPXL/DPTR，避免打断主循环正在进行的
 * MOVC/XDATA 访问。播放循环用绝对截止时间调度，让 OLED 整屏刷新与音符发声
 * 重叠，避免刷屏时间叠加到乐曲节奏上。
 *
 * 上电时会用 Ms_Delay(10) 校准 ticks/ms：正常情况下约 2765，万一 Timer0
 * 被配置成 1T（约 33178）或其它频率也能自动适配；若计时器完全不动，则退回
 * 原来的 Ms_Delay 播放节奏（慢一点但保证能播）。
 */

void MusicClock_Init(void);

/* 手动补一次计时采样。整屏刷屏期间主循环没有读时钟，OLED_Staff_Show 会在
 * 渲染完和刷屏完各调用一次，保证相邻采样间隔远小于 16-bit 定时器的溢出周期
 *（约 23.7ms）。 */
void MusicClock_Poll(void);

/* 重置调度期限为当前时刻，一首曲子开始时调用。 */
void MusicClock_Reset(void);

/* 等到当前调度期限；事件 0 会立即返回。 */
void MusicClock_WaitDeadline(void);

/* 当前事件播放完后，把调度期限推进 durationMs 毫秒。 */
void MusicClock_Advance(uint32_t durationMs);

#endif
