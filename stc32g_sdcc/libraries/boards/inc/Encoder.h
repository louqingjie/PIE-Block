#ifndef _ENCODER_H
#define _ENCODER_H

#include "common.h"

typedef struct
{
	uint8_t	TIMN_enum;				//�����������
	uint8_t	GPIN_enum;				//�жϷ�������
	uint8_t Dir;              //��ת����
	uint16_t pouse;           //����
	uint16_t pouse_last;     //��һʱ������
  int pouse_t;            //ʵ������ֵ
	int pouse_read;
} Encoder_TypeDef;

void Encoder_Init(void);
int Encoder_Count_Read(void);
void Encoder_Clear(void);

#endif


