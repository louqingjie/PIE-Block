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

/* =====================================================
 * 链路失效保护：Timer0 1 ms 轮询时基 + 接收质量计数
 *
 * 设计要点：
 * - 不使用定时器中断：SDCC 的 ISR 入口不保存 DPXL，1 ms 中断里访问 XDATA
 *   会破坏主循环正在进行的代码/XDATA 访问（与 MusicClock 同一结论）。
 * - Timer0 12T 自由计数，主上下文轮询差值；采样点放在 nrf_handler()、
 *   RemoteStatusSend() 和生成代码的阻塞收包助手里，保证相邻采样间隔远小于
 *   16-bit 溢出周期（约 23.7 ms）。
 * - 有效帧刷新 last_rx；age 超过 RC_LINK_TIMEOUT_MS 时清零 rc_ctrl 并置
 *   KEY_RCDISCONNECTED，生成代码据此进入安全状态；收到新帧自动恢复。
 * ===================================================================== */
#define RC_LINK_TICKS_PER_MS (FOSC / 12000UL)

RC_LinkStats_t rc_link_stats;

static uint8_t rc_link_clock_started;
static uint8_t rc_link_lost;
static uint16_t rc_link_ms;
static uint16_t rc_link_last_rx_ms;
static uint16_t rc_link_timer_last;
static uint32_t rc_link_timer_acc;

static uint16_t RcLinkReadTimer(void)
{
  uint8_t hi;
  uint8_t lo;
  uint8_t hi_again;

  for (;;)
  {
    hi = TH0;
    lo = TL0;
    hi_again = TH0;
    if (hi == hi_again)
      return (uint16_t)(((uint16_t)hi_again << 8) | (uint16_t)lo);
  }
}

void RcLinkClockInit(void)
{
  if (rc_link_clock_started)
    return;

  TR0 = 0;
  TF0 = 0;
  ET0 = 0;                    /* 纯轮询，不开放 Timer0 中断 */
  AUXR &= (uint8_t)~0x80;      /* Timer0 固定 12T，与 RC_LINK_TICKS_PER_MS 一致 */
  TMOD = (uint8_t)((TMOD & 0xF0u) | 0x01u); /* Timer0 mode 1：16 位自由计数 */
  TH0 = 0;
  TL0 = 0;
  TR0 = 1;

  rc_link_ms = 0;
  rc_link_last_rx_ms = 0;
  rc_link_lost = 0;
  rc_link_timer_acc = 0;
  rc_link_timer_last = RcLinkReadTimer();
  rc_link_clock_started = 1;
}

static void RcLinkPoll(void)
{
  uint16_t now;
  uint16_t delta;

  if (!rc_link_clock_started)
    return;

  now = RcLinkReadTimer();
  delta = (uint16_t)(now - rc_link_timer_last);
  rc_link_timer_last = now;
  rc_link_timer_acc += (uint32_t)delta;
  while (rc_link_timer_acc >= RC_LINK_TICKS_PER_MS)
  {
    rc_link_timer_acc -= RC_LINK_TICKS_PER_MS;
    rc_link_ms++;
  }
}

void RcLinkService(void)
{
  if (!rc_link_clock_started)
    return;

  RcLinkPoll();
  if (!rc_link_lost &&
      (uint16_t)(rc_link_ms - rc_link_last_rx_ms) > RC_LINK_TIMEOUT_MS)
  {
    rc_link_lost = 1;
    rc_link_stats.timeouts++;
    /* 不再沿用旧值：清零输入并置断链标志，生成代码据此输出安全值。 */
    memset(&rc_ctrl, 0, sizeof(rc_ctrl));
    rc_ctrl.key.value |= (uint16_t)(1u << KEY_RCDISCONNECTED);
  }
}

uint16_t RcLinkAgeMs(void)
{
  return (uint16_t)(rc_link_ms - rc_link_last_rx_ms);
}

uint8_t RcLinkIsLost(void)
{
  return rc_link_lost;
}

void remote_control_init(void)
{
  uint8_t retry;

  /* NRF 初始化：20 次有界重试。模块缺失时不永久卡死，交给断链保护进入安全状态。 */
  for (retry = 0; retry < 20; retry++)
  {
    if (NRF24L01_Init())
      break;
    Ms_Delay(10);
  }

  memset(&sendpack, 0, sizeof(SendPack_t));

  Ms_Delay(200);
}

// ң����Э����
uint8_t Rc_unpack_data(uint8_t *data_t)
{
  int i;
  uint8_t check = 0;
  if (data_t[0] != 11)
  {
    rc_link_stats.header_error++;
    return 0; /* 帧头校验失败 */
  }
  for (i = 1; i < 11; i++)
    check += data_t[i];
  if (check != data_t[11])
  {
    rc_link_stats.checksum_error++;
    return 0; /* 帧尾校验失败 */
  }

  rc_ctrl.rocker.value[0] = (int16_t)(data_t[1] | data_t[2] << 8);
  rc_ctrl.rocker.value[1] = (int16_t)(data_t[3] | data_t[4] << 8);
  rc_ctrl.rocker.value[2] = (int16_t)(data_t[5] | data_t[6] << 8);
  rc_ctrl.rocker.value[3] = (int16_t)(data_t[7] | data_t[8] << 8);
  rc_ctrl.key.value = (uint16_t)(data_t[9] | data_t[10] << 8);

  /* 收到有效帧：刷新链路年龄并退出安全状态。 */
  rc_link_last_rx_ms = rc_link_ms;
  rc_link_lost = 0;
  rc_link_stats.valid++;
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

// ��������ָ��
SendPack_t *get_sendpack_point(void)
{
  return &sendpack;
}


