#include "STC32Gxx.h"

/* 最小固件也覆盖最高中断向量，便于检查启动/向量布局。 */
void Default_Isr(void) __interrupt (64)
{
}
