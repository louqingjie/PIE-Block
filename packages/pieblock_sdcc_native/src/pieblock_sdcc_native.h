#ifndef PIEBLOCK_SDCC_NATIVE_H
#define PIEBLOCK_SDCC_NATIVE_H

#include <stdint.h>

#if defined(_WIN32)
#define PB_SDCC_EXPORT __declspec(dllexport)
#else
#define PB_SDCC_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define PB_SDCC_API_VERSION 5u

typedef enum pb_sdcc_operation_kind {
  PB_SDCC_OPERATION_COMPILE_UNIT = 1,
  PB_SDCC_OPERATION_LINK = 2
} pb_sdcc_operation_kind;

typedef enum pb_sdcc_status {
  PB_SDCC_OK = 0,
  PB_SDCC_BUSY = 1,
  PB_SDCC_INVALID_ARGUMENT = 2,
  PB_SDCC_UNAVAILABLE = 3,
  PB_SDCC_IO_ERROR = 4,
  PB_SDCC_CANCELED = 5,
  PB_SDCC_RUNNING = 6,
  PB_SDCC_COMPLETE = 7,
  PB_SDCC_EVENT_AVAILABLE = 8
} pb_sdcc_status;

typedef enum pb_sdcc_stage {
  PB_SDCC_STAGE_PREPARING = 0,
  PB_SDCC_STAGE_PREPROCESSING = 1,
  PB_SDCC_STAGE_COMPILING = 2,
  PB_SDCC_STAGE_ASSEMBLING = 3,
  PB_SDCC_STAGE_LINKING = 4,
  PB_SDCC_STAGE_DONE = 5
} pb_sdcc_stage;

typedef enum pb_sdcc_level {
  PB_SDCC_LEVEL_INFO = 0,
  PB_SDCC_LEVEL_WARNING = 1,
  PB_SDCC_LEVEL_ERROR = 2
} pb_sdcc_level;

typedef struct pb_sdcc_string_list {
  const char *const *items;
  uint32_t count;
} pb_sdcc_string_list;

typedef struct pb_sdcc_request {
  int32_t operation_kind;
  const char *working_directory;
  const char *resource_directory;
  const char *project_kind;
  const char *source_path;
  const char *object_output_path;
  pb_sdcc_string_list object_paths;
  pb_sdcc_string_list library_object_paths;
  pb_sdcc_string_list arguments;
  const char *hex_output_path;
  const char *map_output_path;
  const char *log_output_path;
} pb_sdcc_request;

typedef struct pb_sdcc_event {
  int32_t stage;
  int32_t level;
  int32_t current;
  int32_t total;
  const char *file_name;
  const char *message;
} pb_sdcc_event;

typedef struct pb_sdcc_result {
  int32_t status;
  int32_t exit_code;
  int32_t error_count;
  int32_t warning_count;
  const char *hex_path;
  const char *map_path;
  const char *log_path;
  const char *error_code;
  const char *message;
} pb_sdcc_result;

typedef struct pb_sdcc_operation pb_sdcc_operation;

PB_SDCC_EXPORT uint32_t pb_sdcc_api_version(void);
PB_SDCC_EXPORT const char *pb_sdcc_build_fingerprint(void);
PB_SDCC_EXPORT int32_t pb_sdcc_is_available(void);
PB_SDCC_EXPORT pb_sdcc_status pb_sdcc_start(
    const pb_sdcc_request *request,
    pb_sdcc_operation **operation);
PB_SDCC_EXPORT pb_sdcc_status pb_sdcc_poll_event(
    pb_sdcc_operation *operation,
    pb_sdcc_event *event);
PB_SDCC_EXPORT pb_sdcc_status pb_sdcc_cancel(pb_sdcc_operation *operation);
PB_SDCC_EXPORT pb_sdcc_status pb_sdcc_get_result(
    pb_sdcc_operation *operation,
    pb_sdcc_result *result);
PB_SDCC_EXPORT void pb_sdcc_destroy(pb_sdcc_operation *operation);

#ifdef __cplusplus
}
#endif

#endif
