/*********************************************************************************************************************
 *     COPYRIGHT NOTICE
 *     Copyright (c) 2023,CNU_W.PIE
 *     All rights reserved.
 *     ���⺯���ο�STC�ٷ�������
 *     ��ע�������⣬�����������ݰ�Ȩ�������ָ������У�δ������������������ҵ��;��
 *     �޸�����ʱ���뱣��PP�İ�Ȩ������
 *     Except where indicated, the copyright of all the contents below is owned by PP 
 *     and can not be used for commercial purposes without permission. 
 *     The copyright notice of PP must be preserved when modifying the content.
 *
 * @file       CNU_PIE_WDog.c
 * @brief      WDog
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#include "CNU_PIE_WDog.h"
 /**************************************************************************************************************************
 * @brief  ���Ź���ʼ������
 * @param[in]  WDT   �ṹ����,��ο�WDT.h��Ķ���
***************************************************************************************************************************/
void WDog_Init(WDog_InitTypeDef *WDT)
{
	if(WDT->WDT_Enable == ENABLE)		EN_WDT = 1;	//ʹ�ܿ��Ź�

	WDT_PS_Set(WDT->WDT_PS);	//���Ź���ʱ��ʱ�ӷ�Ƶϵ��		WDT_SCALE_2,WDT_SCALE_4,WDT_SCALE_8,WDT_SCALE_16,WDT_SCALE_32,WDT_SCALE_64,WDT_SCALE_128,WDT_SCALE_256
	if(WDT->WDT_IDLE_Mode == WDT_IDLE_STOP)	IDL_WDT = 0;	//IDLEģʽֹͣ����
	else									IDL_WDT = 1;	//IDLEģʽ��������
}

 /**************************************************************************************************************************
 * @brief  ������Ź���ʼ������ ι��
***************************************************************************************************************************/
void WDog_Clear (void)
{
	CLR_WDT = 1;    // ι��
}

