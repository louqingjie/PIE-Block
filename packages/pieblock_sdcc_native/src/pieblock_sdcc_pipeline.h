#ifndef PIEBLOCK_SDCC_PIPELINE_H
#define PIEBLOCK_SDCC_PIPELINE_H

#include <stdatomic.h>

#include "pieblock_sdcc_native.h"

typedef void (*pb_sdcc_pipeline_event_fn)(
    void *context,
    pb_sdcc_stage stage,
    pb_sdcc_level level,
    int current,
    int total,
    const char *message);

int pb_sdcc_pipeline_execute(
    const pb_sdcc_request *request,
    const atomic_bool *cancel_requested,
    pb_sdcc_pipeline_event_fn emit,
    void *emit_context,
    int *warning_count,
    char *message,
    unsigned long message_size);

#endif
