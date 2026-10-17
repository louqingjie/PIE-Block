/*
 * 主机侧比对工装：把 voice_synth.c 编成原生程序，打印每个 8 位样本，
 * 由 check_voice_model.py 与 voice_model.py 的定点模型逐样本比对。
 *
 * 编译（由脚本完成）：
 *   gcc -DVOICE_CODE= -I<工程 inc 目录> voice_synth.c host_check_main.c host_check_data.c
 */
#include <stdio.h>

#include "voice_synth.h"

/* 由 check_voice_model.py 生成的同目录数据文件。 */
extern const uint8_t voiceFramesTest[];
extern const unsigned int voiceFramesTestCount;

int main(void)
{
    unsigned long total = (unsigned long)voiceFramesTestCount * VOICE_HOP_SAMPLES;
    unsigned long index;
    VoiceSynth_Start(voiceFramesTest, (uint16_t)voiceFramesTestCount);
    for (index = 0; index < total; index++)
        printf("%u\n", (unsigned)VoiceSynth_NextSample());
    return 0;
}
