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
 * @file       common.c
 * @brief      ͨ��
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#include "common.h"
#include "intrins.h"
#include "CNU_PIE_GPIO.h"

/*
 * Keil C251 与 SDCC MCS-251 为同一段 C 延时循环生成的指令数量不同。
 * SDCC 的 while(--i) 包含字节判断、零判断和 EJMP，循环体明显更长；
 * 继续沿用 Keil 的 /6000、/7000000 会让所有软件延时（尤其是音乐节拍）
 * 变慢。SDCC 取约 2/3 的迭代次数，保持与 Keil 的实测节拍接近。
 */
#if defined(__SDCC)
#define DELAY_MS_DIVISOR 9000UL
#define DELAY_US_DIVISOR 10500000UL
#else
#define DELAY_MS_DIVISOR 6000UL
#define DELAY_US_DIVISOR 7000000UL
#endif
volatile unsigned int DELAY_MS = 0;
volatile unsigned int DELAY_US = 0;
unsigned long system_clock;
 /**************************************************************************************************************************
 * @brief  ������ʱ��Ƶ��
 * @note   �ڲ������û��������
 * @param[in]  NULL
 * @retval  ���õ���ʱ��Ƶ��
***************************************************************************************************************************/
uint32_t System_Clock_Set(void)
{
	system_clock = FOSC;
	P_SW2 |= 0x80;//ʹ�ܷ�������Ĵ���
	switch (system_clock)
	{
		case 22118400://22.1184MHz
			CLKDIV = 0x04; IRTRIM = T22M_ADDR; VRTRIM = VRT27M_ADDR;
		  IRCBAND = 0x02; CLKDIV = 0x00; break;
		case 24000000://24MHz
		  CLKDIV = 0x04; IRTRIM = T24M_ADDR; VRTRIM = VRT27M_ADDR;
		  IRCBAND = 0x02; CLKDIV = 0x00; break;
    case 27000000://27MHz
			CLKDIV = 0x04; IRTRIM = T27M_ADDR; VRTRIM = VRT27M_ADDR;
		  IRCBAND = 0x02; CLKDIV = 0x00; break;
		case 30000000://30MHz
			CLKDIV = 0x04; IRTRIM = T30M_ADDR; VRTRIM = VRT27M_ADDR;
		  IRCBAND = 0x02; CLKDIV = 0x00; break;
		case 33177600://33.1776MHz
			CLKDIV = 0x04; IRTRIM = T33M_ADDR; VRTRIM = VRT27M_ADDR;
		  IRCBAND = 0x02; CLKDIV = 0x00; break;
		case 35000000://35MHz
			CLKDIV = 0x04; IRTRIM = T35M_ADDR; VRTRIM = VRT44M_ADDR;
		  IRCBAND = 0x03; CLKDIV = 0x00; break;
    default://Ĭ��35MHz
			CLKDIV = 0x04; IRTRIM = T35M_ADDR; VRTRIM = VRT44M_ADDR;
		  IRCBAND = 0x03; CLKDIV = 0x00; break;
	}
	return system_clock;
}
 /**************************************************************************************************************************
 * @brief  ��ʱ������ʼ��
 * @note   �ڲ������û��������
 * @param[in]  NULL
 * @retval     NULL
***************************************************************************************************************************/
void Delay_Init(void)
{
	DELAY_MS = system_clock / DELAY_MS_DIVISOR;
	DELAY_US = system_clock / DELAY_US_DIVISOR;
	if(system_clock <= 12000000) DELAY_US++;//����Ӧ��ʱ��
}
 /**************************************************************************************************************************
 * @brief  �Ĵ����������
 * @note   �ڲ������û��������
 * @param[in]  NULL
 * @retval     NULL
***************************************************************************************************************************/
void Register_Set(void)
{
	EAXFR = 1;				// ʹ�ܷ���XFR
	CKCON = 0x00;			// �����ⲿ��������Ϊ���
	WTST = 0;
	RSTCFG |= P54RST_MASK;	      // ʹP54Ϊ��λ����
	P_SW2 = 0x80;			// ���������ַ����
	//if(System_Clock_Set() != 35000000)  WTST = 0;//CPU��ȡ����洢���ĵȴ�ʱ�� 0Ϊ���
	//else WTST = 0x07; //����Ƶ��35MHzʱ��Ƶ��������Ҫ���õȴ�ʱ����Ĭ��Ϊ7��ʱ������	
#if (1 == EXTERNAL_CRYSTA_ENABLE)
	XOSCCR = 0xc0; 			//�����ⲿ����
	while (!(XOSCCR & 1)); 	//�ȴ�ʱ���ȶ�
	CLKDIV = 0x00; 			//ʱ�Ӳ���Ƶ
	CLKSEL = 0x01; 			//ѡ���ⲿ����
#else
	//�Զ�����ϵͳƵ��
	#if (33177600 == FOSC)
		system_clock = System_Clock_Set();
	#else
		system_clock = FOSC;
	#endif
#endif
	 
	Delay_Init();       //��ʱ������ʼ��
	//ENLVR = 0;        // ��ֹ������͵�ѹ��λ
	
	WTST = 0;
  P_SW2 |= 0x80;
  CLKDIV = 0;				//24MHz��Ƶ����Ƶ����
	
	P0M0 = 0x00;P0M1 = 0x00;// P0
	P1M0 = 0x00;P1M1 = 0x00;// P1
	P2M0 = 0x00;P2M1 = 0x00;// P2
	P3M0 = 0x00;P3M1 = 0x00;// P3
	P4M0 = 0x00;P4M1 = 0x00;// P4
  P5M0 = 0x00;P5M1 = 0x00;// P5
	P6M0 = 0x00;P6M1 = 0x00;// P6
	P7M0 = 0x00;P7M1 = 0x00;// P7
	
	ADCCFG = 0;
	AUXR = 0;
	SCON = 0;
	S2CON = 0;
	S3CON = 0;
	S4CON = 0;
	P_SW1 = 0;
	IE2 = 0;
	TMOD = 0;
}
 /**************************************************************************************************************************
 * @brief  ���뼶��ʱ����
 * @note   ʵ�ֺ�����ʱ������Ӧ��ʱ��
 * @param[in]  ��ʱʱ��
 * @retval     NULL
***************************************************************************************************************************/
void Ms_Delay(uint16_t ms)
{
	uint16_t i;
	do{
		i = DELAY_MS;
		while(--i);
	}while(--ms);
}
 /**************************************************************************************************************************
 * @brief  ΢�뼶��ʱ����
 * @note   ʵ��΢����ʱ������Ӧ��ʱ�ӣ���׼ȷ��ʱ
 * @param[in]  ��ʱʱ��
 * @retval     NULL
***************************************************************************************************************************/
void Us_Delay(uint32_t us)
{
	uint16_t i;
	do {
			i = DELAY_US;
			while(--i);
	   }while(--us);
}
 /**************************************************************************************************************************
 * @brief  ����ȫ���ж�
 * @note   ��ֹ�ж�
 * @param[in]  NULL
 * @retval     NULL
***************************************************************************************************************************/
void DisableGlobalIRQ(void)
{
	EA = 0;
}
 /**************************************************************************************************************************
 * @brief  ����ȫ���ж�
 * @note   ��ʼ�ж�
 * @param[in]  NULL
 * @retval     NULL
***************************************************************************************************************************/
void EnableGlobalIRQ(void)
{
	EA = 1;
}
 /**************************************************************************************************************************
 * @brief  �������ʼ��
 * @note   �Ĵ�������+�ж��Ƿ���+��ʱ��ʼ��
 * @param[in]  NULL
 * @retval     NULL
***************************************************************************************************************************/
void Board_Init(void)
{
	Register_Set();    //�Ĵ�������
	EnableGlobalIRQ();//����ȫ���ж�
}

