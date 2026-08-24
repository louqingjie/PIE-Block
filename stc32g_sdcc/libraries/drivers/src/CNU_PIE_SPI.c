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
 * @file       CNU_PIE_SPI.c
 * @brief      SPI
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#include "CNU_PIE_SPI.h"
#include "CNU_PIE_GPIO.h"

uint8_t 	SPI_RxTimerOut;
uint8_t 	SPI_BUF_type SPI_RxBuffer[SPI_BUF_LENTH];
__bit B_SPI_Busy; //����æ��־

 /**************************************************************************************************************************
 * @brief  SPI��ʼ��
 * @exampleCode
 *      SPI_Init(SPI_1, 1 , SPI_LSB , SPI_CPOL_High , SPI_CPHA_2Edge , SPI_Speed_16 , SPI_Mode_Master , 1); //��ʼ��SPI1 , ����CS���� CPOL�� CPHA˫�� ʱ�ӷ�Ƶ16��Ƶ ����ģʽ ����SPI
 * @endcode
 * @param[in]  SPI_CHN    SPI��� 
 * @param[in]  SS_CFG     �Ƿ�����SS����              
 * @param[in]  FirstBit   SPI����ģʽ
 * @param[in]  cpol/cpha  SPIʱ��/��λ���Կ���
 * @param[in]  Clock_Div  SPI��������
 * @param[in]  SPI_Mode   SPI����/�ӻ�
 * @param[in]  SPI_EN     �Ƿ���SPI
***************************************************************************************************************************/
void SPI_Init(SPI_ENUM SPI_CHN , uint8_t SS_CFG , uint8_t FirstBit , uint8_t cpol , uint8_t cpha , uint8_t Clock_Div , uint8_t SPI_Mode , uint8_t SPI_EN)
{
		switch(SPI_CHN)
  {
    case SPI_1:P_SW1 |= (0x00<<2);
        break;
    case SPI_2:P_SW1 |= (0x01<<2);
        break;
    case SPI_3:P_SW1 |= (0x02<<2);
        break;
    case SPI_4:P_SW1 |= (0x03<<2);
        break;
  }
	if(SS_CFG) SSIG = 0;//ʹ��SS ͨ��SS����ȷ�����豸���Ǵ��豸
	else SSIG = 1;      //����SS ͨ��SPIģʽѡ�������豸
	SPEN = SPI_EN;      //ʹ��SPI
  DORD = FirstBit;    //ѡ�����ģʽ ���MSB С��LSB
	MSTR = SPI_Mode;   //��������
	CPOL = cpol;        //SPIʱ�Ӽ��Կ���
	CPHA = cpha;        //SPIʱ����λ����
	SPCTL = (SPCTL & ~0x03) | (Clock_Div);//�ٶ�/SPIʱ�ӷ�Ƶ����
	SPI_RxTimerOut = 0;
	B_SPI_Busy = 0;
}
 /**************************************************************************************************************************
 * @brief  SPI��ʼ��
 * @exampleCode
 *      SPI_SetMode(SPI_Mode_Slave); //����SPIΪ�ӻ�ģʽ
 * @endcode
 * @param[in]  SPI_Mode   SPIģʽ
***************************************************************************************************************************/
void SPI_SetMode(uint8_t SPI_Mode)
{
	if(SPI_Mode == SPI_Mode_Slave)
	{
		MSTR = 0; 	//��������Ϊ�ӻ�����
		SSIG = 0; 	//SS����ȷ������
	}
	else
	{
		MSTR = 1; 	//ʹ�� SPI ����ģʽ
		SSIG = 1; 	//����SS���Ź���
	}
}
 /**************************************************************************************************************************
 * @brief  SPIдһ���ֽ�����
 * @exampleCode
 *      SPI_WriteByte(0xFF); //SPIдһ���ֽ����� 0xff
 * @endcode
 * @param[in]  dat   SPIд�������
***************************************************************************************************************************/
void SPI_WriteByte(uint8_t dat)
{
	if(ESPI)
	{
		B_SPI_Busy = 1;
		SPDAT = dat;
		while(B_SPI_Busy);  //�ж�ģʽ
	}
	else
	{
		SPDAT = dat;
		while(SPIF == 0); //��ѯģʽ
	  {SPIF = 1; WCOL = 1;}  //���SPIF��WCOL��־
	}
}
 /**************************************************************************************************************************
 * @brief  SPI��ȡһ���ֽ�����
 * @exampleCode
 * uint8_t data;
 * data = SPI_ReadByte(); //SPI��ȡһ���ֽ�����
 * @endcode
 * @retval data   SPI��ȡ������
***************************************************************************************************************************/
uint8_t SPI_ReadByte(void)
{
	SPDAT = 0xff;
	while(SPIF == 0) ;
	{SPIF = 1; WCOL = 1;}    //��0 SPIF��WCOL��־
	return (SPDAT);
}

uint8_t SPI_ReadWriteByte(uint8_t TxData)
{
    SPDAT = TxData;					        //DATA�Ĵ�����ֵ
    while (!(SPSTAT & 0x80));  		//��ѯ��ɱ�־
    SPSTAT = 0xc0;                //���жϱ�־
	  return SPDAT;
}


