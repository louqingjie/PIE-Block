#ifndef BUZZER_VOICE_SMOKE_VOICE_SYNTH_H
#define BUZZER_VOICE_SMOKE_VOICE_SYNTH_H

#include <stdint.h>

/*
 * 参数表与增益表都放在代码段。主机侧做“C 与 Python 逐样本比对”时，
 * 用 -DVOICE_CODE= 编译即可让这两份源码脱离 SDCC 的存储类型限定符。
 */
#ifndef VOICE_CODE
#define VOICE_CODE __code
#endif

#define VOICE_ORDER 10
/* 帧格式：周期 + 混合比 + 增益 + ORDER 个反射系数。
 * 必须与 tools/voice/voice_model.py 的 FRAME_BYTES 一致（逐样本比对会验证）。 */
#define VOICE_FRAME_BYTES (3 + VOICE_ORDER)
/* 帧率 100 帧/秒；采样率 7.2kHz（Timer0 重载 60928 = 65536-4608）-> 每帧 72 样本。 */
#define VOICE_HOP_SAMPLES 72
#define VOICE_INTERP_STEPS 8
#define VOICE_SAMPLES_PER_STEP (VOICE_HOP_SAMPLES / VOICE_INTERP_STEPS)
/* 无声样本值：50% 占空比。0 和 255 是直流，同样无声，但 128 是线性中点。 */
#define VOICE_PWM_IDLE 128

/* 增益字节 -> 线性增益（8*残差 RMS 的开方压扩），由参数生成器产出。 */
extern const uint16_t VOICE_CODE voiceGainTable[256];

/* 输出压缩曲线（幂函数）：峰值不动、抬高平均电平，补偿压电片效率低导致的听感偏轻。 */
extern const uint8_t VOICE_CODE voiceCompressionTable[256];

/* 开始播放一段参数表；frame_count 为 0 表示保持静音。 */
void VoiceSynth_Start(const uint8_t VOICE_CODE *frames, uint16_t frame_count);
/* 取下一个 8 位 PWM 样本（0..255）。非阻塞，供定时器中断按采样率调用。 */
uint8_t VoiceSynth_NextSample(void);
/* 参数表播完（含尾部淡出帧）后返回 0。 */
uint8_t VoiceSynth_IsActive(void);

#endif /* BUZZER_VOICE_SMOKE_VOICE_SYNTH_H */
