/*
 * remote_control.h
 *
 *  Created on: 2020��4��5��
 *      Author: Фʱ��
 */

#ifndef __REMOTE_CONTROL_H_     
#define __REMOTE_CONTROL_H_     

#include "common.h"

// �������
//--------------------------------------------------------------
typedef enum
{
  
  KEY_OFFSET_WKUP        =      0, 	// ���Ѽ�
  KEY_OFFSET_1	         =      1, 	// ����1
  KEY_OFFSET_UP	         =      2, 	// ��
  KEY_OFFSET_DOWN        =      3, 	// ��
  KEY_OFFSET_LEFT        =      4, 	// ��
  KEY_OFFSET_RIGHT       =      5, 	// ��
  KEY_OFFSET_A	         =      6, 	// A
  KEY_OFFSET_B 	         =      7, 	// B
  KEY_OFFSET_C	         =      8, 	// C
  KEY_OFFSET_D 	         =      9, 	// D
  KEY_OFFSET_Rocker11    =      10,	// ҡ��1�İ��� 
  KEY_OFFSET_Rocker21    =      11,	// ҡ��2�İ���
  
  KEY_RCDISCONNECTED     =      15,     //ң��������״̬
  
}KEY_OFFSET_t;

//ҡ�����
//--------------------------------------------------------------
typedef enum
{
  
  ROCKER_LEFT_VERTICAL    =      0,         //��ҡ����ֱ����
  ROCKER_LEFT_HORIZONTAL  =      1,         //��ҡ��ˮƽ����
  ROCKER_RIGHT_VERTICAL   =      2,         //��ҡ����ֱ����
  ROCKER_RIGHT_HORIZONTAL =      3,         //��ҡ��ˮƽ����
  
}ROCKER_OFFSET_t;


//ң��������Э����ṹ��
#pragma pack(1)//һ�ֽڶ���
typedef struct
{
	#pragma pack(1)//һ�ֽڶ���
  struct 
  {	
    int16_t value[4];		
  }rocker;
	#pragma  pack()
  
	#pragma pack(1)//һ�ֽڶ���
  struct
  {	
    uint16_t value;	
  }key;
	#pragma  pack()
  
}RC_ctrl_t;
#pragma  pack()

//����ʾ����
typedef struct LineText_t 
{
  char Name[5];
  uint8_t Namelenth;
  float Number[2];
  uint8_t Row;
  uint8_t Size;
}LineText_t;

//�������ݰ�
typedef struct SendPack_t
{
  LineText_t line[6];
  uint8_t Mode[6]; //0��������  1���ַ�����С�ڵ���5��+���� 2������ + ���� 3������
}SendPack_t;


/*
*ң������ʼ��
*/
void remote_control_init(void); 

/*
*@brief ��ȡң��������ֵ
*@param ������� 
*@return ���·���1 �ɿ�����0 ������󷵻�-1
*/
int8_t RcKeyValueRead(KEY_OFFSET_t offset);

/*
*@brief ��ȡң����ҡ��adc�ɼ�ֵ
*@param  ҡ�����
*@return ���ض�Ӧ����adc�ɼ�ֵ
*/
int16_t RcRockerValueRead(ROCKER_OFFSET_t offset);

/*
*@brief �������Լ�������ʾ�ڶ�Ӧ����
*@param ��ʾ�����׵�ַ
*@param ��ʾ���ֳ��� ���Ϊ5���ַ� 
*@param ��ʾ����
*@param λ��ң���������� 0-5 ��6�� ������Ч
*@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
*@example Send_Data("abcd", 3, 2.55, 0, 0); //������Ϊ3���ַ��� abc �� ���� 2.55 ��6*8�ӵ�0����ʾ
*/
void ShowStringData(char* name_t, uint8_t namelenth, float num, uint8_t row, uint8_t Size);

/*
*@brief ������������������ʾ�ڶ�Ӧ����
*@param ��ʾ������
*@param ��ʾ������
*@param λ��ң���������� 0-5 ��6�� ������Ч
*@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
*@example ShowData(1.0, 0.2, 0, 1); //������ 1 �� 0.2 �� 8*16 �Ĵ�С�ӵ�0����ʾ
*/
void ShowData(float numleft, float numright, uint8_t row, uint8_t Size);


/*
*@brief ���ĳһ����ʾ����
*@param λ��ң���������� 0-5 ��6�� ������Ч
*@param ��С ��0��һ�����һ�� ����0��һ���������
*@example ShowLineClear(0, 1);  //�����0,1�е���ʾ����
*/
void ShowLineClear(uint8_t row, uint8_t Size);



//�·������û��������
uint8_t Rc_unpack_data(uint8_t* data_t); //Э�������
SendPack_t* get_sendpack_point(void);

#endif      //__REMOTE_CONTROL_H_     
