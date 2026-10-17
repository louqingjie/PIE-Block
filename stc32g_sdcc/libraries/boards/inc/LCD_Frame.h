#ifndef LCD_FRAME_H
#define LCD_FRAME_H

#include <stdint.h>

/* 把 1024 字节页格式帧缓冲整屏写到 OLED（SSD1306 页寻址）。
 * 独立于 LCD.c 的内部函数实现，避免修改厂商文件。 */
void LCD_WriteFrame(const uint8_t *frame1024);

#endif /* LCD_FRAME_H */
