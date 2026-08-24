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
	DELAY_MS = system_clock / 6000UL;
	DELAY_US = system_clock / 7000000UL;
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
	/* P_SW2 不是普通可位寻址 SFR；整字节设置，避免 SDCC 把 EAXFR 写到错误位地址。 */
	P_SW2 |= 0x80;			// ʹ�ܷ���XFR
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
  CLKDIV = 0;				// SYSCLK = MCLK，不分频

  /*
   * STC32G 的 HSPWM/HSSPI 时钟独立于 CPU 时钟：
   * HSCLK = HSIOCK / HSCLKDIV。
   * HSCLKDIV 复位值为 2（实际二分频），而 PWM 库按 system_clock
   * 计算周期，因此这里必须明确选择 MCLK 且关闭高速时钟分频。
   */
  CLKSEL &= (uint8_t)~0x40;	// HSPWM/HSSPI 使用 MCLK
  HSCLKDIV = 0x00;				// HSPWM/HSSPI 不分频
	
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
#if defined(__SDCC) && (FOSC == 33177600UL)
/*
 * Keil C251 在 33.1776 MHz 下对：
 *
 *     unsigned long edata i;
 *     _nop_();
 *     i = 8293UL;
 *     while (i) i--;
 *
 * 生成 MOV DR4,#02065H / DEC DR4,#01H / JNE。SDCC 的 C 后端目前会把
 * 同样的 32 位循环展开成逐字节判断，不能使用相同的计数值获得相同的
 * 时间，因此这里保留 Keil 的两条指令循环作为明确的 SDCC 校准基准。
 */
static void Delay1000us_Reference(void)
{
	__asm
		nop
		mov dr4,#0x2065
	00001$:
		dec dr4,#0x01
		jne 00001$
	__endasm;
}

/* Keil 33.1776 MHz 的 Delay1us：计数值为 7。 */
static void Delay1us_Reference(void)
{
	__asm
		mov dr4,#0x0007
	00002$:
		dec dr4,#0x01
		jne 00002$
	__endasm;
}
#endif

void Ms_Delay(uint16_t ms)
{
#if defined(__SDCC) && (FOSC == 33177600UL)
	while (ms > 0)
	{
		ms--;
		Delay1000us_Reference();
	}
#else
	uint16_t i;
	do{
		i = DELAY_MS;
		while(--i);
	}while(--ms);
#endif
}
 /**************************************************************************************************************************
 * @brief  ΢�뼶��ʱ����
 * @note   ʵ��΢����ʱ������Ӧ��ʱ�ӣ���׼ȷ��ʱ
 * @param[in]  ��ʱʱ��
 * @retval     NULL
***************************************************************************************************************************/
void Us_Delay(uint32_t us)
{
#if defined(__SDCC) && (FOSC == 33177600UL)
	while (us > 0UL)
	{
		us--;
		Delay1us_Reference();
	}
#else
	uint16_t i;
	do {
			i = DELAY_US;
			while(--i);
	   }while(--us);
#endif
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

