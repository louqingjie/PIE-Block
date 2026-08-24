/*********************************************************************************************************************
 *     COPYRIGHT NOTICE
 *     Copyright (c) 2023,CNU_W.PIE
 *     All rights reserved.
 *
 *     ��ע�������⣬�����������ݰ�Ȩ�������ָ������У�δ������������������ҵ��;��
 *     �޸�����ʱ���뱣��PP�İ�Ȩ������
 *     Except where indicated, the copyright of all the contents below is owned by PP 
 *     and can not be used for commercial purposes without permission. 
 *     The copyright notice of PP must be preserved when modifying the content.
 *
 * @file       CNU_PIE_TIMER.h
 * @brief      TIMER
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#ifndef __CNU_PIE_TIMER_H_
#define __CNU_PIE_TIMER_H_

#include "STC32Gxx.h"
#include "common.h"


typedef enum
{
	TIMER0_P34 = 0,
	TIMER1_P35,
	TIMER2_P12,
	TIMER3_P04,
	TIMER4_P06,
}TIMER_COUNT_PIN_Enum;

typedef enum
{
	TIM0= 0,
	TIM1,
	TIM2,
	TIM3,
	TIM4,
}TIMER_CHN_Enum;

void Timer_Count_Init(TIMER_COUNT_PIN_Enum Timer_Count_Pin);
uint16_t Timer_Count_Read(TIMER_COUNT_PIN_Enum Timer_Count_Pin);
void Timer_Count_Clear(TIMER_COUNT_PIN_Enum Timer_Count_Pin);
void PIT_Timer_Ms(TIMER_CHN_Enum Timer_CHN , uint16_t Time);
void PIT_Timer_Clear(TIMER_CHN_Enum Timer_CHN);
#endif
