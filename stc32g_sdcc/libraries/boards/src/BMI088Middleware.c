#include "BMI088Middleware.h"
#include "common.h"


void BMI088_GPIO_init(void)
{

}

void BMI088_com_init(void)
{


}

void BMI088_delay_ms(uint16_t ms)
{

    Ms_Delay(ms);
}

void BMI088_delay_us(uint16_t us)
{
    Us_Delay(us);
}
void BMI088_ACCEL_NS_L(void)
{
    P22 = 0;//����Ӳ���޸�
}
void BMI088_ACCEL_NS_H(void)
{
    P22 = 1;//����Ӳ���޸�
}
void BMI088_GYRO_NS_L(void)
{
    P27 = 0;//����Ӳ���޸�
}
void BMI088_GYRO_NS_H(void)
{
    P27 = 1;//����Ӳ���޸�
}

uint8_t BMI088_read_write_byte(uint8_t txdata)
{
    SPDAT = txdata;				       	//DATA�Ĵ�����ֵ
    while (!(SPSTAT & 0x80));  		//��ѯ��ɱ�־
    SPSTAT = 0xc0;                //���жϱ�־
	  return SPDAT;
}



