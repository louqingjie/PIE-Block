/*
 * 主机侧比对工装：把 voice_synth.c 编成原生程序，供 check_voice_model.py 比对。
 *
 * 两种模式（编译时都要带 -DVOICE_CODE= -DVOICE_HOST_BUILD）：
 *   host_check.exe            打印整段语料的每个 8 位样本
 *   host_check.exe arith      穷举打印 MulQ8 / Lerp 的边界结果
 */
#include <stdio.h>
#include <string.h>

#include "voice_synth.h"

/* 由 check_voice_model.py 生成的同目录数据文件。 */
extern const uint8_t voiceFramesTest[];
extern const unsigned int voiceFramesTestCount;

#ifdef VOICE_HOST_BUILD
/* voice_synth.c 里的测试包装（仅在 VOICE_HOST_BUILD 下编译）。 */
extern int16_t VoiceSynth_TestMulQ8(int8_t q, int16_t value);
extern int16_t VoiceSynth_TestLerp(int16_t previous, int16_t current, uint16_t weight);

static const int16_t ARITH_VALUES[] =
{
    -32768, -32767, -16384, -8192, -4096, -1024, -256, -255, -128, -127, -1,
    0, 1, 127, 128, 255, 256, 1024, 4096, 8192, 16384, 32766, 32767
};

/* lerp_q8 的契约是 |current - previous| <= 255，所以分两组合法端点。 */
static const int16_t LERP_SIGNED[] = { -127, -100, -64, -1, 0, 1, 64, 100, 127 };

static const int16_t LERP_UNSIGNED[] = { 0, 1, 64, 127, 128, 200, 254, 255 };

static const uint16_t LERP_WEIGHTS[] = { 0, 32, 64, 96, 128, 160, 192, 256 };

static void DumpLerpGrid(const int16_t *endpoints, int count)
{
    int i;
    int j;
    int w;
    for (i = 0; i < count; i++)
    {
        for (j = 0; j < count; j++)
        {
            for (w = 0; w < (int)(sizeof(LERP_WEIGHTS) / sizeof(LERP_WEIGHTS[0])); w++)
                printf("L %d %d %d %d\n", (int)endpoints[i], (int)endpoints[j],
                       (int)LERP_WEIGHTS[w],
                       (int)VoiceSynth_TestLerp(endpoints[i], endpoints[j],
                                                LERP_WEIGHTS[w]));
        }
    }
}

static void DumpArithmetic(void)
{
    int q;
    int i;
    for (q = -127; q <= 127; q++)
    {
        for (i = 0; i < (int)(sizeof(ARITH_VALUES) / sizeof(ARITH_VALUES[0])); i++)
            printf("M %d %d %d\n", q, (int)ARITH_VALUES[i],
                   (int)VoiceSynth_TestMulQ8((int8_t)q, ARITH_VALUES[i]));
    }
    DumpLerpGrid(LERP_SIGNED, (int)(sizeof(LERP_SIGNED) / sizeof(LERP_SIGNED[0])));
    DumpLerpGrid(LERP_UNSIGNED, (int)(sizeof(LERP_UNSIGNED) / sizeof(LERP_UNSIGNED[0])));
}
#endif /* VOICE_HOST_BUILD */

int main(int argc, char **argv)
{
    unsigned long total;
    unsigned long index;

#ifdef VOICE_HOST_BUILD
    if (argc > 1 && strcmp(argv[1], "arith") == 0)
    {
        DumpArithmetic();
        return 0;
    }
#endif
    (void)argc;
    (void)argv;

    total = (unsigned long)voiceFramesTestCount * VOICE_HOP_SAMPLES;
    VoiceSynth_Start(voiceFramesTest, (uint16_t)voiceFramesTestCount);
    for (index = 0; index < total; index++)
        printf("%u\n", (unsigned)VoiceSynth_NextSample());
    return 0;
}
