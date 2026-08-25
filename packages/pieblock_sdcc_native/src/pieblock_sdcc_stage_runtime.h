#ifndef PIEBLOCK_SDCC_STAGE_RUNTIME_H
#define PIEBLOCK_SDCC_STAGE_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*pb_sdcc_stage_entry)(int argc, char **argv);

int pb_sdcc_stage_entries_available(void);
int pb_sdcc_invoke_stage(pb_sdcc_stage_entry entry, int argc, char **argv);

#ifdef __cplusplus
}
#endif

#endif
