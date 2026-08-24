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
 * @file       CNU_PIE_ADC.c
 * @brief      ADC
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#include "CNU_PIE_ADC.h"
 /**************************************************************************************************************************
 * @brief  ADC��ʼ������
 * @exampleCode
 *      ADC_Init(ADC_P10 , ADC_SPEED_2X16T); //ADC P10���ų�ʼ��ΪADC ��ʱ�ӷ�ƵADC_SPEED_2X16T
 * @endcode
 * @param[in]  ADC_PIN   ADC����
 * @param[in]  ADC_SPEED ADCʱ�ӷ�Ƶϵ��
***************************************************************************************************************************/
void ADC_Init(ADC_PIN_ENUM ADC_PIN , ADC_SPEED_ENUM ADC_SPEED)
{
	ADC_CONTR |= 1<<7;				
	ADC_CONTR &= (0xF0);		
	ADC_CONTR |= ADC_PIN;
	
	if((ADC_PIN >> 3) == 1) //P0�˿�
	{
		//IO����Ҫ����Ϊ��������
		P0M0 &= ~(1 << (ADC_PIN & 0x07));
		P0M1 |= (1 << (ADC_PIN & 0x07));
	}
	else if((ADC_PIN >> 3) == 0) //P1�˿�	
	{
		//IO����Ҫ����Ϊ��������
		P1M0 &= ~(1 << (ADC_PIN & 0x07));
	  P1M1 |= (1 << (ADC_PIN & 0x07));
	}

	ADCCFG |= ADC_SPEED&0x0F;			//Fosc_ADC = SYSCLK/2(SPEED+1)
	
	ADCCFG |= 1<<5;					//ת������Ҷ��롣 ADC_RES �������ĸ� 2 λ�� ADC_RESL �������ĵ� 8 λ��
}
 /**************************************************************************************************************************
 * @brief  ADC��ʼ������
 * @exampleCode
 *      uint16_t data;
 *      data = ADC_Init(ADC_P10 , ADC_12BIT); //ADC P10��ȡһ������ 12λ����
 * @endcode
 * @retval ADC_Value   ADC��ȡһ�ε�����
***************************************************************************************************************************/
uint16_t ADC_Read_Once(ADC_PIN_ENUM ADC_PIN , uint8_t Precision)
{
	uint16_t ADC_Value;
	
	ADC_CONTR &= (0xF0);			//���ADC_CHS[3:0] �� ADC ģ��ͨ��ѡ��λ
	ADC_CONTR |= ADC_PIN;
	
	ADC_CONTR |= 0x40;  			// ���� AD ת��
	while (!(ADC_CONTR & 0x20));  	// ��ѯ ADC ��ɱ�־
	ADC_CONTR &= ~0x20;  			// ����ɱ�־
	
	ADC_Value = ADC_RES;  			//�洢 ADC �� 12 λ����ĸ� 4 λ
	ADC_Value <<= 8;
	ADC_Value |= ADC_RESL;  		//�洢 ADC �� 12 λ����ĵ� 8 λ
	
	ADC_RES = 0;
	ADC_RESL = 0;
	
	ADC_Value >>= Precision;		//ȡ����λ
	
	return ADC_Value;
}
 /**************************************************************************************************************************
 * @brief  ADC����ȡ��+�˲�����ֵð�ݣ�����
 * @exampleCode
 *      uint16_t data;
 *      data = ADC_Average(ADC_P10 , ADC_12BIT , 10); //ADC P10��ȡʮ������ 12λ���� ����һ������
 * @endcode
 * @retval ADC_Value   ADC��ȡһ�ε�����
***************************************************************************************************************************/
uint16_t ADC_Average(ADC_PIN_ENUM ADC_PIN , uint8_t Precision , uint8_t N) 
{
  uint32_t sum=0;
  uint8_t M=N;
	int i=0;
	int j=0;
  int str[20]={0};
  for(i=0;i<N;i++)str[i]=ADC_Read_Once(ADC_PIN,Precision);
  for(i=1;i<N;i++)
    for(j=0;j<N-i;j++)
    {
      if(str[j]>str[j+1])
      {
        int t=str[j+1];
        str[j+1]=str[j];
        str[j]=t;
      }
    }
  for(i=1;i<N-1;i++)sum+=str[i];
  return ((uint16_t)(sum/M));
}


