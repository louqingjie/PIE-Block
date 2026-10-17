#ifndef BUZZER_VOICE_SMOKE_MAIN_H
#define BUZZER_VOICE_SMOKE_MAIN_H

#include "STC32Gxx.h"
#include "common.h"
#include "CNU_PIE_GPIO.h"
#include "CNU_PIE_PWM.h"
#include "CNU_PIE_TIMER.h"

/* 由 main.c 提供：每次 Timer0 采样中断推进一个合成样本并刷新 PWM。 */
void VoiceTimerTick(void);

#endif /* BUZZER_VOICE_SMOKE_MAIN_H */
