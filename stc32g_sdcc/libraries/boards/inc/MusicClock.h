#ifndef STC32G_SDCC_MUSIC_CLOCK_H
#define STC32G_SDCC_MUSIC_CLOCK_H

#include <stdint.h>

/*
 * 音乐固件的毫秒级时间基准：Timer0 16-bit 自由计数（12T），溢出中断里
 * 只累加 0x10000，因此中断延迟不会丢计数。播放循环用绝对截止时间调度，
 * 让 OLED 整屏刷新与音符发声重叠，避免刷屏时间叠加到乐曲节奏上。
 */

void MusicClock_Init(void);

/* 重置调度期限为当前时刻，一首曲子开始时调用。 */
void MusicClock_Reset(void);

/* 等到当前调度期限；事件 0 会立即返回。 */
void MusicClock_WaitDeadline(void);

/* 当前事件播放完后，把调度期限推进 durationMs 毫秒。 */
void MusicClock_Advance(uint32_t durationMs);

#endif
