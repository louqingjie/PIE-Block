#ifndef BUZZER_VOICE_SMOKE_VOICE_DATA_H
#define BUZZER_VOICE_SMOKE_VOICE_DATA_H

#include <stdint.h>

/* 由 stc32g_sdcc/tools/voice/make_voice_params.py 生成，请勿手工修改。 */
#define VOICE_FRAME_BYTES 13
#define VOICE_HOP_SAMPLES 80
#define VOICE_SAMPLE_RATE_HZ 8000
#define VOICE_GAIN_FULL_SCALE 32493

extern const uint16_t voiceGainTable[256];
extern const uint8_t voiceFramesPLiuling[3302];
#define VOICE_FRAMES_PLIULING_COUNT 254
extern const uint8_t voiceFramesPLiushi[3328];
#define VOICE_FRAMES_PLIUSHI_COUNT 256

#endif /* BUZZER_VOICE_SMOKE_VOICE_DATA_H */
