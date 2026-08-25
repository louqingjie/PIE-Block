#ifndef PIEBLOCK_SDCC_STAGE_RUNTIME_H
#define PIEBLOCK_SDCC_STAGE_RUNTIME_H

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*pb_sdcc_stage_entry)(int argc, char **argv);

int pb_sdcc_stage_entries_available(void);
int pb_sdcc_embedded_host_self_test(void);
void pb_sdcc_reset(void);
int pb_sdcc_invoke_stage(pb_sdcc_stage_entry entry, int argc, char **argv);
int pb_sdcc_system(const char *command);
FILE *pb_sdcc_popen(const char *command, const char *mode);
int pb_sdcc_pclose(FILE *stream);

#ifdef __cplusplus
}
#endif

#endif
