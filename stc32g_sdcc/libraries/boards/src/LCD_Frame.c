/* 整屏写 1024B 页格式帧缓冲（SSD1306 页寻址）。
 *
 * 独立的命令/数据位操作实现，不改厂商 LCD.c/LCD.h：命令序列与 LCD.c 的
 * LCD_Fill 完全一致（0xB0+page、0x01、0x10，然后 128 个数据字节）。
 * 之所以不直接调用 LCD_WrCmd/LCD_WrDat：它们在 LCD.c 里是 extern 定义，
 * 但厂商 LCD.h 没有声明（固件约束见 docs/design/OLED五线谱显示方案.md）。
 */

#include <stdint.h>

#include "LCD_Frame.h"

#include "intrins.h"
#include "LCD.h"

static void LCD_FrameWriteByte(uint8_t value, uint8_t isData)
{
    uint8_t bitsLeft = 8u;

    OLED_CS_Clear();
    if (isData != 0u)
    {
        OLED_DC_Set();
    }
    else
    {
        OLED_DC_Clear();
    }
    OLED_CLK_Clear();
    while (bitsLeft--)
    {
        if ((value & 0x80u) != 0u)
        {
            OLED_D1_Set();
        }
        else
        {
            OLED_D1_Clear();
        }
        OLED_CLK_Set();
        _nop_();
        OLED_CLK_Clear();
        value <<= 1;
    }
    OLED_CS_Set();
}

void LCD_WriteFrame(const uint8_t *frame1024)
{
    uint8_t page;
    uint8_t x;
    const uint8_t *source = frame1024;

    if (frame1024 == 0)
    {
        return;
    }
    for (page = 0u; page < 8u; page++)
    {
        LCD_FrameWriteByte((uint8_t)(0xB0u + page), 0u);
        LCD_FrameWriteByte(0x01u, 0u);
        LCD_FrameWriteByte(0x10u, 0u);
        for (x = 0u; x < 128u; x++)
        {
            LCD_FrameWriteByte(source[x], 1u);
        }
        source += 128;
    }
}
