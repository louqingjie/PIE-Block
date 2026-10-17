#ifndef OLED_STAFF_H
#define OLED_STAFF_H

#include <stdint.h>

#include "StaffRender.h"

/* 初始化 OLED（调用 LCD.c 的 LCD_Init，含上电 logo/清屏）。 */
void OLEDStaff_Init(void);

/* 渲染第 index 帧并整屏刷到 OLED；index 必须 < song->count。 */
void OLEDStaff_Show(const StaffSong *song, uint16_t index);

#endif /* OLED_STAFF_H */
