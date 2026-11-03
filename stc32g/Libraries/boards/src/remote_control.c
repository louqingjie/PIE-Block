/*
 * remote_control.c
 *
 *  Created on: 2020��4��5��
 *      Author: Фʱ��
 */
#include "CNU_PIE_TIMER.h"
#include "remote_control.h"
#include "nrf24l01.h"
#include "main.h"

RC_ctrl_t rc_ctrl;   // ң����ʵ�廯
SendPack_t sendpack; // ��������ʵ�廯

// ң������ʼ��
void remote_control_init(void)
{
  // Ci24R1��ʼ��
  while (!NRF24L01_Init())
    ;
  // NRF24L01_Init();

  memset(&sendpack, 0, sizeof(SendPack_t));

  // ��ʼ�����������ж�
  // PIT4�ж����� 1ms�ж�

  // PIT_Timer_Ms(TIM4, 1);

  Ms_Delay(200);
}

// ң����Э����
uint8_t Rc_unpack_data(uint8_t *data_t)
{
  int i;
  uint8_t check = 0;
  if (data_t[0] != 11)
    return 0; // ֡ͷУ��ʧ��
  for (i = 1; i < 11; i++)
    check += data_t[i];
  if (check != data_t[11])
    return 0; // ֡βУ��ʧ��

  // ���
  rc_ctrl.rocker.value[0] = (int16_t)(data_t[1] | data_t[2] << 8);
  rc_ctrl.rocker.value[1] = (int16_t)(data_t[3] | data_t[4] << 8);
  rc_ctrl.rocker.value[2] = (int16_t)(data_t[5] | data_t[6] << 8);
  rc_ctrl.rocker.value[3] = (int16_t)(data_t[7] | data_t[8] << 8);
  rc_ctrl.key.value = (uint16_t)(data_t[9] | data_t[10] << 8);
  return 1;
}

/*
 *@brief �������Լ�������ʾ�ڶ�Ӧ����
 *@param ��ʾ�����׵�ַ
 *@param ��ʾ���ֳ��� ���Ϊ5���ַ�
 *@param ��ʾ����
 *@param λ��ң���������� 0-5 ��6�� ������ʾ
 *@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
 *@example ShowStringData("abc", 3, 2.55, 0, 1);
 */
void ShowStringData(char *name_t, uint8_t namelenth, float num, uint8_t row, uint8_t Size)
{
  if (row > 5 || (name_t == 0 && namelenth != 0) || sendpack.Mode[row])
    return;
  if (namelenth > 5)
    namelenth = 5;
  memcpy(sendpack.line[row].Name, name_t, namelenth);
  sendpack.line[row].Namelenth = namelenth;
  sendpack.line[row].Number[0] = num;
  sendpack.line[row].Row = row;
  sendpack.line[row].Size = Size ? 1 : 0;
  sendpack.Mode[row] = 1;
}

/*
 *@brief ������������������ʾ�ڶ�Ӧ����
 *@param ��ʾ������
 *@param ��ʾ������
 *@param λ��ң���������� 0-5 ��6�� ������ʾ
 *@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
 *@example ShowData(1.0, 0.2, 0, 1);
 */
void ShowData(float numleft, float numright, uint8_t row, uint8_t Size)
{
  if (row > 5 || sendpack.Mode[row])
    return;
  sendpack.line[row].Number[0] = numleft;
  sendpack.line[row].Number[1] = numright;
  sendpack.line[row].Row = row;
  sendpack.line[row].Size = Size ? 1 : 0;
  sendpack.Mode[row] = 2;
}

/*
 *@brief ���ĳһ����ʾ����
 *@param λ��ң���������� 0-5 ��6�� ������Ч
 *@param ��С ��0��һ�����һ�� ����0��һ���������
 *@example ShowLineClear(0, 1);  //�����0,1�е���ʾ����
 */
void ShowLineClear(uint8_t row, uint8_t Size)
{
  if (row > 5)
    return;
  sendpack.line[row].Row = row;
  sendpack.line[row].Size = Size ? 1 : 0;
  sendpack.Mode[row] = 3;
}

/*
 *@brief ��ȡң��������ֵ
 *@param �������
 *@return ���·���1 �ɿ�����0 ������󷵻�-1
 */
int8_t RcKeyValueRead(KEY_OFFSET_t offset)
{
  if (offset > 15)
    return -1;
  return (rc_ctrl.key.value & (1 << offset)) ? 1 : 0;
}

/*
 *@brief ��ȡң����ҡ��adc�ɼ�ֵ
 *@param  ҡ�����
 *@return ���ض�Ӧ����adc�ɼ�ֵ
 */
int16_t RcRockerValueRead(ROCKER_OFFSET_t offset)
{
  return rc_ctrl.rocker.value[offset];
}

// �жϻص�����
static uint32_t timeline = 0; // ʱ����
uint8_t Clear_Time = 0;       // ң�����Ͽ��������
float Offset = 0;             // �첽����ƫ����
void TM4_Isr() interrupt 20
{
  PIT_Timer_Clear(TIM4);
  timeline++;
  if ((timeline % 20) == 0) // 20ms ����һ��
  {
    RCPacket_Send();
  }
  Clear_Time++;
  if (Clear_Time >= 50) // 50msδ���յ�ң�������������������Ϣ
  {
    Clear_Time = 0;
    memset(&rc_ctrl, 0, sizeof(rc_ctrl));
    rc_ctrl.key.value |= 1 << KEY_RCDISCONNECTED;
  }
}
// ��������ָ��
SendPack_t *get_sendpack_point(void)
{
  return &sendpack;
}
