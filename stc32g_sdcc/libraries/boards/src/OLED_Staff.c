/* OLED 五线谱显示入口：持有一块 1024B 帧缓冲，渲染后整屏刷到 OLED。
 *
 * 帧缓冲放在 static：SDCC --model-large 下未初始化 static 数组自动落 XSEG
 * （链接参数 --xram-loc 0x010000 / --xram-size 0x2000 的 8KB XRAM），
 * 不占用 251 的 iram，也不占栈。构建后用 .asm/.map 的 XSEG 段确认。
 */

#include <stdint.h>

#include "OLED_Staff.h"

#include "LCD.h"
#include "LCD_Frame.h"
#include "MusicClock.h"

static uint8_t staffFrame[STAFF_FRAME_BYTES];

void OLEDStaff_Init(void)
{
    LCD_Init();
}

void OLEDStaff_Show(const StaffSong *song, uint16_t index)
{
    StaffRender_DrawFrame(song, index, staffFrame);
    /* 渲染/刷屏各约几毫秒：中途补采样，保证 16-bit Timer0 不丢溢出计数。 */
    MusicClock_Poll();
    LCD_WriteFrame(staffFrame);
    MusicClock_Poll();
}
