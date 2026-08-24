#include "STC32Gxx.h"

/* 音乐测试不使用中断，保留默认入口以覆盖未使用的中断向量。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}
