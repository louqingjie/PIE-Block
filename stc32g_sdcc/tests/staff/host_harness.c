/* 主机对拍：逐场景、逐帧调用固件 StaffRender_DrawFrame，与 Dart 渲染器生成的
 * golden 帧（1024B SSD1306 页格式）逐字节比较。
 *
 * fixture 由另一个任务生成（stc32g_sdcc/tests/staff/fixtures/）：
 *   staff_fixture.h                 —— StaffSong 数据表 + staffFixtureScenarios[]
 *   golden/<name>_<frame:03d>.bin   —— 每个场景每个事件一帧
 *
 * 用法：host_harness <fixtures_dir>
 *   退出码 0 = 全部一致，1 = 有差异/文件缺失，2 = 参数错误。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "StaffRender.h"
#include "staff_fixture.h"

#define HARNESS_MAX_DIFF_REPORTS 24

static uint8_t actualFrame[STAFF_FRAME_BYTES];
static uint8_t goldenFrame[STAFF_FRAME_BYTES];

static int ReadGoldenFrame(const char *fixturesDir, const char *name,
                           uint16_t frameIndex, uint8_t *out)
{
    char path[768];
    FILE *file;
    size_t bytesRead;

    snprintf(path, sizeof(path), "%s/golden/%s_%03u.bin", fixturesDir, name,
             (unsigned)frameIndex);
    file = fopen(path, "rb");
    if (file == NULL)
    {
        fprintf(stderr, "[FAIL] 打不开 golden 帧: %s\n", path);
        return 0;
    }
    bytesRead = fread(out, 1u, STAFF_FRAME_BYTES, file);
    fclose(file);
    if (bytesRead != STAFF_FRAME_BYTES)
    {
        fprintf(stderr, "[FAIL] golden 帧长度不是 %d 字节: %s (%u bytes)\n",
                STAFF_FRAME_BYTES, path, (unsigned)bytesRead);
        return 0;
    }
    return 1;
}

/* 差异定位：offset -> page / x / 具体 y 位，便于和 Dart 渲染色对照。 */
static void ReportDiff(const char *name, uint16_t frameIndex,
                       unsigned offset, uint8_t expected, uint8_t actual)
{
    unsigned page = offset / STAFF_WIDTH;
    unsigned x = offset % STAFF_WIDTH;
    unsigned xored = (unsigned)expected ^ (unsigned)actual;
    int bit;

    printf("  帧 %s[%03u] byte %u (page %u, x %u): golden=0x%02X actual=0x%02X\n",
           name, (unsigned)frameIndex, offset, page, x, (unsigned)expected,
           (unsigned)actual);
    for (bit = 0; bit < 8; bit++)
    {
        if ((xored & (1u << bit)) != 0u)
        {
            printf("    y=%u (page*8+bit=%d) golden_bit=%u actual_bit=%u\n",
                   (unsigned)(page * 8u + (unsigned)bit), bit,
                   (unsigned)(((unsigned)expected >> bit) & 1u),
                   (unsigned)(((unsigned)actual >> bit) & 1u));
        }
    }
}

static int RunScenario(const char *fixturesDir, const char *name,
                       const StaffSong *song)
{
    uint16_t frameIndex;
    unsigned diffBytes = 0u;
    unsigned diffFrames = 0u;
    unsigned reported = 0u;

    if (song == NULL)
    {
        fprintf(stderr, "[FAIL] 场景 %s: song 指针为空\n", name);
        return 0;
    }
    printf("场景 %-12s：%u 帧", name, (unsigned)song->count);
    for (frameIndex = 0u; frameIndex < song->count; frameIndex++)
    {
        unsigned offset;

        if (ReadGoldenFrame(fixturesDir, name, frameIndex, goldenFrame) == 0)
        {
            return 0;
        }
        StaffRender_DrawFrame(song, frameIndex, actualFrame);
        for (offset = 0u; offset < STAFF_FRAME_BYTES; offset++)
        {
            if (goldenFrame[offset] != actualFrame[offset])
            {
                diffBytes++;
                if (reported < HARNESS_MAX_DIFF_REPORTS)
                {
                    ReportDiff(name, frameIndex, offset, goldenFrame[offset],
                               actualFrame[offset]);
                    reported++;
                }
            }
        }
        if (memcmp(goldenFrame, actualFrame, STAFF_FRAME_BYTES) != 0)
        {
            diffFrames++;
        }
    }
    if (diffBytes == 0u)
    {
        printf("  -> PASS\n");
        return 1;
    }
    printf("  -> FAIL：%u/%u 帧不一致，%u 字节不同（只列前 %u 处）\n",
           diffFrames, (unsigned)song->count, diffBytes,
           (unsigned)HARNESS_MAX_DIFF_REPORTS);
    return 0;
}

int main(int argc, char **argv)
{
    const char *fixturesDir;
    size_t scenarioCount =
        sizeof(staffFixtureScenarios) / sizeof(staffFixtureScenarios[0]);
    size_t i;
    int ok;

    if (argc > 2)
    {
        fprintf(stderr, "用法: %s [fixtures_dir]\n", argv[0]);
        return 2;
    }
    fixturesDir = argc == 2 ? argv[1] : "stc32g_sdcc/tests/staff/fixtures";

    printf("固件 StaffRender.c 对拍：%u 个场景，%d 字节/帧\n",
           (unsigned)scenarioCount, STAFF_FRAME_BYTES);
    ok = 1;
    for (i = 0; i < scenarioCount; i++)
    {
        const StaffFixtureScenario *scenario = &staffFixtureScenarios[i];

        if (scenario->name == NULL || scenario->song == NULL)
        {
            fprintf(stderr, "[FAIL] 场景 #%u 的 name/song 为空\n",
                    (unsigned)i);
            ok = 0;
            continue;
        }
        if (RunScenario(fixturesDir, scenario->name, scenario->song) == 0)
        {
            ok = 0;
        }
    }
    if (ok != 0)
    {
        printf("[PASS] 全部 %u 个场景与 golden 帧逐字节一致\n",
               (unsigned)scenarioCount);
        return 0;
    }
    printf("[FAIL] 固件渲染与 golden 帧不一致（见上方差异）\n");
    return 1;
}
