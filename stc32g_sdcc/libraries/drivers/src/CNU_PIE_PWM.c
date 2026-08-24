/*********************************************************************************************************************
 *     COPYRIGHT NOTICE
 *     Copyright (c) 2023,CNU_W.PIE
 *     All rights reserved.
 *     ���⺯���ο���ɿƼ���Դ��STC������
 *     ��ע�������⣬�����������ݰ�Ȩ�������ָ������У�δ������������������ҵ��;��
 *     �޸�����ʱ���뱣��PP�İ�Ȩ������
 *     Except where indicated, the copyright of all the contents below is owned by PP 
 *     and can not be used for commercial purposes without permission. 
 *     The copyright notice of PP must be preserved when modifying the content.
 *
 * @file       CNU_PIE_PWM.c
 * @brief      PWM
 * @author     ����
 * @version    v1.1
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#include "CNU_PIE_PWM.h"
#include "CNU_PIE_GPIO.h"

//����Ƚ�ģʽ�Ĵ���
const uint32_t PWM_CCMR_ADDR[] = {0x7efec8, 0x7efec9, 0x7efeca ,0x7efecb, 0x7efee8, 0x7efee9, 0x7efeea, 0x7efeeb};
//����Ƚ�ʹ�ܼĴ���
const uint32_t PWM_CCER_ADDR[] = {0x7efecc, 0x7efecd, 0x7efeec ,0x7efeed};
//���ƼĴ���,��8λ��ַ  ��8λ��ַ + 1����
const uint32_t PWM_CCR_ADDR[] = {0x7efed5, 0x7efed7, 0x7efed9, 0x7efedb, 0x7efef5, 0x7efef7, 0x7efef9, 0x7efefb};	
//���ƼĴ���,��8λ��ַ  ��8λ��ַ + 1����
const uint32_t PWM_ARR_ADDR[] = {0x7efed2,0x7efef2};

/* PWMA/PWMB高级PWM寄存器通过HSPWM异步窗口访问。 */
static void PWM_WriteA(uint32_t address, uint8_t value)
{
	while (HSPWMA_ADR & 0x80);
	HSPWMA_DAT = value;
	HSPWMA_ADR = ((uint8_t)address) & 0x7F;
}

static uint8_t PWM_ReadA(uint32_t address)
{
	uint8_t value;
	while (HSPWMA_ADR & 0x80);
	HSPWMA_ADR = (((uint8_t)address) & 0x7F) | 0x80;
	while (HSPWMA_ADR & 0x80);
	value = HSPWMA_DAT;
	return value;
}

static void PWM_WriteB(uint32_t address, uint8_t value)
{
	while (HSPWMB_ADR & 0x80);
	HSPWMB_DAT = value;
	HSPWMB_ADR = ((uint8_t)address) & 0x7F;
}

static uint8_t PWM_ReadB(uint32_t address)
{
	uint8_t value;
	while (HSPWMB_ADR & 0x80);
	HSPWMB_ADR = (((uint8_t)address) & 0x7F) | 0x80;
	while (HSPWMB_ADR & 0x80);
	value = HSPWMB_DAT;
	return value;
}

 /**************************************************************************************************************************
 * @brief  ��ʼ��PWM����IOģʽ
 * @brief  �ڲ����ã��������
***************************************************************************************************************************/
void PWM_PIN_SET(PWM_CHN_PIN_enum PWM_CHN_PIN)
{
	switch(PWM_CHN_PIN)
	{
		case PWMA_CH1P_P10: GPIO_Init(GPIO_P1,GPIO_Pin_0,GPIO_OUT_PP); break;
		case PWMA_CH1N_P11: GPIO_Init(GPIO_P1,GPIO_Pin_1,GPIO_OUT_PP); break;
		case PWMA_CH1P_P20: GPIO_Init(GPIO_P2,GPIO_Pin_0,GPIO_OUT_PP); break;
		case PWMA_CH1N_P21: GPIO_Init(GPIO_P2,GPIO_Pin_1,GPIO_OUT_PP); break;
		case PWMA_CH1P_P60: GPIO_Init(GPIO_P6,GPIO_Pin_0,GPIO_OUT_PP); break;
		case PWMA_CH1N_P61: GPIO_Init(GPIO_P6,GPIO_Pin_1,GPIO_OUT_PP); break;		
		case PWMA_CH2P_P12: GPIO_Init(GPIO_P1,GPIO_Pin_2,GPIO_OUT_PP); break;
		case PWMA_CH2N_P13: GPIO_Init(GPIO_P1,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMA_CH2P_P22: GPIO_Init(GPIO_P2,GPIO_Pin_2,GPIO_OUT_PP); break;
		case PWMA_CH2N_P23: GPIO_Init(GPIO_P2,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMA_CH2P_P62: GPIO_Init(GPIO_P6,GPIO_Pin_2,GPIO_OUT_PP); break;
		case PWMA_CH2N_P63: GPIO_Init(GPIO_P6,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMA_CH3P_P24: GPIO_Init(GPIO_P2,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMA_CH3N_P25: GPIO_Init(GPIO_P2,GPIO_Pin_5,GPIO_OUT_PP); break;
		case PWMA_CH3P_P64: GPIO_Init(GPIO_P6,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMA_CH3N_P65: GPIO_Init(GPIO_P6,GPIO_Pin_5,GPIO_OUT_PP); break;
		case PWMA_CH4P_P16: GPIO_Init(GPIO_P1,GPIO_Pin_6,GPIO_OUT_PP); break;
		case PWMA_CH4N_P17: GPIO_Init(GPIO_P1,GPIO_Pin_7,GPIO_OUT_PP); break;
		case PWMA_CH4P_P26: GPIO_Init(GPIO_P2,GPIO_Pin_6,GPIO_OUT_PP); break;
		case PWMA_CH4N_P27: GPIO_Init(GPIO_P2,GPIO_Pin_7,GPIO_OUT_PP); break;
		case PWMA_CH4P_P66: GPIO_Init(GPIO_P6,GPIO_Pin_6,GPIO_OUT_PP); break;
		case PWMA_CH4N_P67: GPIO_Init(GPIO_P6,GPIO_Pin_7,GPIO_OUT_PP); break;
		case PWMA_CH4P_P34: GPIO_Init(GPIO_P3,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMA_CH4N_P33:	GPIO_Init(GPIO_P3,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMB_CH1_P20:  GPIO_Init(GPIO_P2,GPIO_Pin_0,GPIO_OUT_PP); break;
		case PWMB_CH1_P17:  GPIO_Init(GPIO_P1,GPIO_Pin_7,GPIO_OUT_PP); break;
		case PWMB_CH1_P00:  GPIO_Init(GPIO_P0,GPIO_Pin_0,GPIO_OUT_PP); break;
		case PWMB_CH1_P74:  GPIO_Init(GPIO_P7,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMB_CH2_P21:  GPIO_Init(GPIO_P2,GPIO_Pin_1,GPIO_OUT_PP); break;
		case PWMB_CH2_P54:  GPIO_Init(GPIO_P5,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMB_CH2_P01:  GPIO_Init(GPIO_P0,GPIO_Pin_1,GPIO_OUT_PP); break;
		case PWMB_CH2_P75:  GPIO_Init(GPIO_P7,GPIO_Pin_5,GPIO_OUT_PP); break;
		case PWMB_CH3_P22:  GPIO_Init(GPIO_P2,GPIO_Pin_2,GPIO_OUT_PP); break;
		case PWMB_CH3_P33:  GPIO_Init(GPIO_P3,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMB_CH3_P02:  GPIO_Init(GPIO_P0,GPIO_Pin_2,GPIO_OUT_PP); break;
		case PWMB_CH3_P76:  GPIO_Init(GPIO_P7,GPIO_Pin_6,GPIO_OUT_PP); break;
		case PWMB_CH4_P23:  GPIO_Init(GPIO_P2,GPIO_Pin_3,GPIO_OUT_PP); break;
		case PWMB_CH4_P34:  GPIO_Init(GPIO_P3,GPIO_Pin_4,GPIO_OUT_PP); break;
		case PWMB_CH4_P03:  GPIO_Init(GPIO_P0,GPIO_Pin_3,GPIO_OUT_PP); break;
    case PWMB_CH4_P77:  GPIO_Init(GPIO_P7,GPIO_Pin_7,GPIO_OUT_PP); break;
	}
}
 /**************************************************************************************************************************
 * @brief  PWM���ų�ʼ��
 * @exampleCode
 *      PWM_Init(PWMA_CH2P_P62, 50, 0); //��ʼ��P62���� Ƶ��50 ��ʼռ�ձ�0
 * @endcode
 * @param[in]  PWM_CHN_PIN PWM���ź� 
 * @param[in]  frequency   PWMƵ��              
 * @param[in]  pwm_duty    PWMռ�ձ�
***************************************************************************************************************************/
void PWM_Init(PWM_CHN_PIN_enum PWM_CHN_PIN , uint32_t frequency , uint32_t pwm_duty)
{
	
	uint32_t match_temp;
	uint32_t period_temp;
	uint16_t Frequency_Division = 0;//��Ƶϵ��
	uint8_t register_value;
	
	P_SW2 |= 0x80;
	
	//GPIO��Ҫ����Ϊ�������
	PWM_PIN_SET(PWM_CHN_PIN);//����Ӧ��IO��������Ϊ�������
	
//	//��Ƶ���㣬���ڼ��㣬ռ�ձȼ���
	Frequency_Division = ( system_clock / frequency ) >> 16;							//���ٷ�Ƶ
	period_temp = system_clock / frequency ;			
	period_temp = period_temp / ( Frequency_Division +1 ) - 1;				//����

	if(pwm_duty != PRECISION)
	{
		match_temp = period_temp * ((float)pwm_duty / PRECISION);	// ռ�ձ�			
	}
	else
	{
		match_temp = (period_temp + 1);								// dutyΪ100%
	}
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)				//PWM5-8
	{
		//ͨ��ѡ������ѡ��
		register_value = PWM_ReadB((uint32_t)&PWMB_ENO);
		register_value |= (1 << ((2 * ((PWM_CHN_PIN >> 4) - 4))));
		PWM_WriteB((uint32_t)&PWMB_ENO, register_value);
		register_value = PWM_ReadB((uint32_t)&PWMB_PS);
		register_value |= ((PWM_CHN_PIN & 0x03) << ((2 * ((PWM_CHN_PIN >> 4) - 4))));
		PWM_WriteB((uint32_t)&PWMB_PS, register_value);
		
		// ����ͨ�����ʹ�ܺͼ���	
		register_value = PWM_ReadB(PWM_CCER_ADDR[PWM_CHN_PIN>>5]);
		register_value |= (uint8_t)(1 << (((PWM_CHN_PIN >> 4) & 0x01) * 4));
		PWM_WriteB(PWM_CCER_ADDR[PWM_CHN_PIN>>5], register_value);
		
		//����Ԥ��Ƶ
		PWM_WriteB((uint32_t)&PWMB_PSCRH, (uint8_t)(Frequency_Division>>8));
		PWM_WriteB((uint32_t)&PWMB_PSCRL, (uint8_t)Frequency_Division);
		
		PWM_WriteB((uint32_t)&PWMB_BKR, 0x80);
		PWM_WriteB((uint32_t)&PWMB_CR1, 0x01);
	}
	else
	{
		register_value = PWM_ReadA((uint32_t)&PWMA_ENO);
		register_value |= (1 << (PWM_CHN_PIN & 0x01)) << ((PWM_CHN_PIN >> 4) * 2);
		PWM_WriteA((uint32_t)&PWMA_ENO, register_value);
		register_value = PWM_ReadA((uint32_t)&PWMA_PS);
		register_value |= ((PWM_CHN_PIN & 0x07) >> 1) << ((PWM_CHN_PIN >> 4) * 2);
		PWM_WriteA((uint32_t)&PWMA_PS, register_value);
		
		// ����ͨ�����ʹ�ܺͼ���	
		register_value = PWM_ReadA(PWM_CCER_ADDR[PWM_CHN_PIN>>5]);
		register_value |= (1 << ((PWM_CHN_PIN & 0x01) * 2 + ((PWM_CHN_PIN >> 4) & 0x01) * 0x04));
		PWM_WriteA(PWM_CCER_ADDR[PWM_CHN_PIN>>5], register_value);

		
		//����Ԥ��Ƶ
		PWM_WriteA((uint32_t)&PWMA_PSCRH, (uint8_t)(Frequency_Division>>8));
		PWM_WriteA((uint32_t)&PWMA_PSCRL, (uint8_t)Frequency_Division);

		PWM_WriteA((uint32_t)&PWMA_BKR, 0x80);
		PWM_WriteA((uint32_t)&PWMA_CR1, 0x01);
	}
	
	//����
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		PWM_WriteB(PWM_ARR_ADDR[PWM_CHN_PIN>>6], (uint8_t)(period_temp>>8));
		PWM_WriteB(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1, (uint8_t)period_temp);
	}
	else
	{
		PWM_WriteA(PWM_ARR_ADDR[PWM_CHN_PIN>>6], (uint8_t)(period_temp>>8));
		PWM_WriteA(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1, (uint8_t)period_temp);
	}

	//���ò���ֵ|�Ƚ�ֵ
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4], (uint8_t)(match_temp>>8));
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
	else
	{
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4], (uint8_t)(match_temp>>8));
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
	
	//��������
	register_value = (PWMB_CH1_P20 <= PWM_CHN_PIN)
		? PWM_ReadB(PWM_CCMR_ADDR[PWM_CHN_PIN>>4])
		: PWM_ReadA(PWM_CCMR_ADDR[PWM_CHN_PIN>>4]);
	register_value |= 0x06<<4;
	register_value |= 1<<3;
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
		PWM_WriteB(PWM_CCMR_ADDR[PWM_CHN_PIN>>4], register_value);
	else
		PWM_WriteA(PWM_CCMR_ADDR[PWM_CHN_PIN>>4], register_value);
}
 /**************************************************************************************************************************
 * @brief  PWM��������ռ�ձ�
 * @exampleCode
 *      PWM_SET_Duty(PWMA_CH2P_P62, 1000); //����P62���� ռ�ձ�1000
 * @endcode
 * @param[in]  PWM_CHN_PIN PWM���ź�             
 * @param[in]  pwm_duty    PWMռ�ձ�
***************************************************************************************************************************/
void PWM_SET_Duty(PWM_CHN_PIN_enum PWM_CHN_PIN , uint32_t pwm_duty)
{
	uint32_t match_temp;
	uint32_t arrange;
	uint8_t register_value;
	
	P_SW2 |= 0x80;//ȷ��ʹ�ܷ���XFR

	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		HSPWMB_CFG = 0x03;
		arrange = ((uint32_t)PWM_ReadB(PWM_ARR_ADDR[PWM_CHN_PIN>>6]) << 8)
			| PWM_ReadB(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1);
	}
	else
	{
		HSPWMA_CFG = 0x03;
		arrange = ((uint32_t)PWM_ReadA(PWM_ARR_ADDR[PWM_CHN_PIN>>6]) << 8)
			| PWM_ReadA(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1);
	}
	
	if(pwm_duty != PRECISION)
	{
		match_temp = arrange * ((float)pwm_duty/PRECISION);				//ռ�ձ�
	}
	else
	{
		match_temp = arrange + 1;
	}
	//���ò���ֵ|�Ƚ�ֵ
	register_value = (uint8_t)(match_temp >> 8);
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4], register_value);
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
	else
	{
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4], register_value);
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
	
}
 /**************************************************************************************************************************
 * @brief  PWM��������Ƶ��
 * @exampleCode
 *      PWM_SET_Frequency (PWMB_CH3_P33,200,5000); //����P33���� Ƶ��200 ռ�ձ�5000
 * @endcode
 * @param[in]  PWM_CHN_PIN PWM���ź� 
 * @param[in]  frequency   PWMƵ��              
 * @param[in]  pwm_duty    PWMռ�ձ�
***************************************************************************************************************************/
void PWM_SET_Frequency(PWM_CHN_PIN_enum PWM_CHN_PIN, uint32_t frequency, uint32_t pwm_duty )
{
	uint32_t match_temp;
	uint32_t period_temp; 
	uint16_t Frequency_Division = 0;//��Ƶϵ��
	
	P_SW2 |= 0x80;//ȷ��ʹ�ܷ���XFR
	
	//��Ƶ���㣬���ڼ��㣬ռ�ձȼ���
	Frequency_Division = (FOSC / frequency) >> 16;							    //��Ƶ
	period_temp = FOSC / frequency ;			
	period_temp = period_temp / (Frequency_Division + 1) - 1;				//����

	if(pwm_duty != PRECISION)//�ж�ռ�ձ��Ƿ���󾫶�
	{
		match_temp = period_temp * ((float)pwm_duty / PRECISION);	// ռ�ձ�			
	}
	else
	{
		match_temp = period_temp + 1;								          //����ռ�ձ�Ϊ���
	}
	
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)//PWMA
	{
		HSPWMB_CFG = 0x03;
		//����Ԥ��Ƶ
		PWM_WriteB((uint32_t)&PWMB_PSCRH, (uint8_t)(Frequency_Division>>8));
		PWM_WriteB((uint32_t)&PWMB_PSCRL, (uint8_t)Frequency_Division);
	}
	else//PWMB
	{
		HSPWMA_CFG = 0x03;
		//����Ԥ��Ƶ
		PWM_WriteA((uint32_t)&PWMA_PSCRH, (uint8_t)(Frequency_Division>>8));
		PWM_WriteA((uint32_t)&PWMA_PSCRL, (uint8_t)Frequency_Division);
	}
	
	//����
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		PWM_WriteB(PWM_ARR_ADDR[PWM_CHN_PIN>>6], (uint8_t)(period_temp>>8));
		PWM_WriteB(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1, (uint8_t)period_temp);
	}
	else
	{
		PWM_WriteA(PWM_ARR_ADDR[PWM_CHN_PIN>>6], (uint8_t)(period_temp>>8));
		PWM_WriteA(PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1, (uint8_t)period_temp);
	}

	//���ò���ֵ|�Ƚ�ֵ
	if(PWMB_CH1_P20 <= PWM_CHN_PIN)
	{
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4], (uint8_t)(match_temp >> 8));
		PWM_WriteB(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
	else
	{
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4], (uint8_t)(match_temp >> 8));
		PWM_WriteA(PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1, (uint8_t)match_temp);
	}
}




