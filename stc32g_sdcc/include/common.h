#ifndef STC32G_SDCC_COMMON_H
#define STC32G_SDCC_COMMON_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "STC32Gxx.h"
#include "intrins.h"

#define FOSC 33177600UL
#define EXTERNAL_CRYSTA_ENABLE 0

#if defined(__SDCC)
#define SDCC_PACKED __attribute__((packed))
#else
#define SDCC_PACKED
#endif

typedef float fp32;
typedef volatile int8_t vint8_t;
typedef volatile int16_t vint16_t;
typedef volatile int32_t vint32_t;
typedef volatile uint8_t vuint8_t;
typedef volatile uint16_t vuint16_t;
typedef volatile uint32_t vuint32_t;

extern uint32_t system_clock;

void Board_Init(void);
void Ms_Delay(uint16_t ms);
void Us_Delay(uint32_t us);
void EnableGlobalIRQ(void);
void DisableGlobalIRQ(void);

#endif
