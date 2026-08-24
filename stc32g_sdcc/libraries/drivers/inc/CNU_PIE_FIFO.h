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
 * @file       CNU_PIE_FIFO.h
 * @brief      FIFO
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
 
#ifndef __CNU_PIE_FIFO_H_
#define __CNU_PIE_FIFO_H_

#include "common.h"

typedef struct
{
    uint8_t     *buffer;                                                          // ����ָ��
    uint32_t    head;                                                             // ����ͷָ�� ����ָ��յĻ���
    uint32_t    end;                                                              // ����βָ�� ����ָ��ǿջ��棨����ȫ�ճ��⣩
    uint32_t    size;                                                             // ����ʣ���С
    uint32_t    max;                                                              // �����ܴ�С
}fifo_struct;

typedef enum
{
    FIFO_SUCCESS,

    FIFO_BUFFER_NULL,
    FIFO_SPACE_NO_ENOUGH,
    FIFO_DATA_NO_ENOUGH,
}fifo_state_enum;

typedef enum
{
    FIFO_READ_AND_CLEAN,
    FIFO_READ_ONLY,
}fifo_operation_enum;

fifo_state_enum   fifo_init           (fifo_struct *fifo, uint8_t *buffer_addr, uint32_t size);
void              fifo_head_offset    (fifo_struct *fifo, uint32_t offset);
void              fifo_end_offset     (fifo_struct *fifo, uint32_t offset);
void              fifo_clear          (fifo_struct *fifo);
uint32_t          fifo_used           (fifo_struct *fifo);

fifo_state_enum fifo_read_buffer    (fifo_struct *fifo, uint8_t *dat, uint32_t *length, fifo_operation_enum flag);
fifo_state_enum fifo_write_buffer   (fifo_struct *fifo, uint8_t *dat, uint32_t length);

#endif

