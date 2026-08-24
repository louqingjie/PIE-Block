#include "STC32Gxx.h"

/* 本测试不使用外设中断，保留默认入口以覆盖未使用的中断向量。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}
