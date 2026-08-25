#include "pieblock_sdcc_pipeline.h"

#include <stdio.h>

/*
 * Integration seam for the MCS-251-only SDCC fork. The ABI and lifecycle are
 * deliberately implemented separately so the compiler, preprocessor,
 * assembler and linker can be landed one stage at a time without changing
 * Dart or Flutter code.
 */
int pb_sdcc_pipeline_execute(
    const pb_sdcc_request *request,
    const atomic_bool *cancel_requested,
    pb_sdcc_pipeline_event_fn emit,
    void *emit_context,
    int *warning_count,
    char *message,
    unsigned long message_size) {
  (void)request;
  (void)cancel_requested;
  (void)warning_count;
  emit(emit_context,
       PB_SDCC_STAGE_PREPARING,
       PB_SDCC_LEVEL_ERROR,
       0,
       0,
       "Android MCS-251 pipeline has not been linked into this build");
  snprintf(message,
           message_size,
           "%s",
           "Android MCS-251 pipeline unavailable");
  return PB_SDCC_UNAVAILABLE;
}
