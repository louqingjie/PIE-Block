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
 * @file       CNU_PIE_EXTI.h
 * @brief      EXTI
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#ifndef __CNU_PIE_EXTI_H_
#define __CNU_PIE_EXTI_H_

#include "STC32Gxx.h"
#include "common.h"

#include "CNU_PIE_GPIO.h"

#define P0_PRI0RITY 0x01
#define P1_PRI0RITY 0x02
#define P2_PRI0RITY 0x04
#define P3_PRI0RITY 0x08
#define P4_PRI0RITY 0x10
#define P5_PRI0RITY 0x20
#define P6_PRI0RITY 0x40
#define P7_PRI0RITY 0x80


extern uint8_t Port_Exti_Flag[8];


typedef enum
{
	FALLING_EDGE = 0,	//�½���
	RISING_EDGE,	    //������
	LOW_LEVEL,        //�͵�ƽ
	HIGH_LEVEL,       //�ߵ�ƽ
}EXTI_MODE_Enum;

typedef enum
{
	Highest_priority = 0,	 //���
	Second_priority,	     //�ڶ�
	Third_priority,        //����
	Lowest_priority,       //���
}EXTI_PRIORITY_Enum;

uint8_t GPIO_EXTI_Init(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin , EXTI_MODE_Enum EXTI_Mode);
uint8_t GPIO_EXTI_Open(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin);
uint8_t GPIO_EXTI_Set_Priority(GPIO_Port_enum GPIO_Port , EXTI_PRIORITY_Enum EXTI_Priority);
uint8_t GPIO_EXTI_Flag_Read(GPIO_Port_enum GPIO_Port);
uint8_t GPIO_EXTI_Flag_Clear(GPIO_Port_enum GPIO_Port);

#endif
