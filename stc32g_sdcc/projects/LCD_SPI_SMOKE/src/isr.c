#include "STC32Gxx.h"

/* 纯 LCD 测试不启用外设中断，为布局检查和异常中断提供统一兜底入口。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}
