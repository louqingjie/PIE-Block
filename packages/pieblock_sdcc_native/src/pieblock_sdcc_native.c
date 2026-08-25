#include "pieblock_sdcc_native.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pieblock_sdcc_pipeline.h"
#include "pieblock_sdcc_stage_runtime.h"

#define PB_EVENT_CAPACITY 128
#define PB_MESSAGE_CAPACITY 1024
#define PB_FILE_NAME_CAPACITY 512

#ifndef PB_SDCC_ANDROID_ABI
#define PB_SDCC_ANDROID_ABI "unknown"
#endif

#ifndef PB_SDCC_PIPELINE_ENABLED
#define PB_SDCC_PIPELINE_ENABLED 0
#endif

#ifndef PB_SDCC_STAGES_LINKED
#define PB_SDCC_STAGES_LINKED 0
#endif

#ifndef PB_SDCC_STAGE_SHA256
#define PB_SDCC_STAGE_SHA256 "unavailable"
#endif

typedef struct pb_owned_request {
  char *working_directory;
  char *resource_directory;
  char *project_kind;
  char *main_source_path;
  char *interrupt_header_path;
  char **source_paths;
  uint32_t source_count;
  char **library_source_paths;
  uint32_t library_source_count;
  char **compile_arguments;
  uint32_t compile_argument_count;
  char **link_arguments;
  uint32_t link_argument_count;
  char *hex_output_path;
  char *map_output_path;
  char *log_output_path;
} pb_owned_request;

typedef struct pb_owned_event {
  int32_t stage;
  int32_t level;
  int32_t current;
  int32_t total;
  char file_name[PB_FILE_NAME_CAPACITY];
  char message[PB_MESSAGE_CAPACITY];
} pb_owned_event;

struct pb_sdcc_operation {
  pthread_t thread;
  pthread_mutex_t mutex;
  atomic_bool cancel_requested;
  int thread_started;
  int thread_joined;
  int complete;
  int32_t status;
  int32_t exit_code;
  int32_t error_count;
  int32_t warning_count;
  pb_owned_request request;
  pb_owned_event events[PB_EVENT_CAPACITY];
  unsigned int event_head;
  unsigned int event_count;
  char last_event_message[PB_MESSAGE_CAPACITY];
  char last_event_file_name[PB_FILE_NAME_CAPACITY];
  char result_message[PB_MESSAGE_CAPACITY];
  char result_error_code[64];
};

static pthread_mutex_t g_build_mutex = PTHREAD_MUTEX_INITIALIZER;
static int g_build_active = 0;

static char *pb_copy_string(const char *value) {
  if (value == NULL) return NULL;
  const size_t size = strlen(value) + 1;
  char *copy = malloc(size);
  if (copy != NULL) memcpy(copy, value, size);
  return copy;
}

static char **pb_copy_strings(const pb_sdcc_string_list *source) {
  if (source->count == 0) return NULL;
  if (source->items == NULL) return NULL;
  char **copies = calloc(source->count, sizeof(*copies));
  if (copies == NULL) return NULL;
  for (uint32_t index = 0; index < source->count; index++) {
    copies[index] = pb_copy_string(source->items[index]);
    if (copies[index] == NULL) {
      for (uint32_t previous = 0; previous < index; previous++) {
        free(copies[previous]);
      }
      free(copies);
      return NULL;
    }
  }
  return copies;
}

static void pb_free_strings(char **values, uint32_t count) {
  if (values == NULL) return;
  for (uint32_t index = 0; index < count; index++) free(values[index]);
  free(values);
}

static void pb_free_request(pb_owned_request *request) {
  free(request->working_directory);
  free(request->resource_directory);
  free(request->project_kind);
  free(request->main_source_path);
  free(request->interrupt_header_path);
  pb_free_strings(request->source_paths, request->source_count);
  pb_free_strings(request->library_source_paths,
                  request->library_source_count);
  pb_free_strings(request->compile_arguments,
                  request->compile_argument_count);
  pb_free_strings(request->link_arguments, request->link_argument_count);
  free(request->hex_output_path);
  free(request->map_output_path);
  free(request->log_output_path);
  memset(request, 0, sizeof(*request));
}

static int pb_request_valid(const pb_sdcc_request *request) {
  return request != NULL && request->working_directory != NULL &&
         request->resource_directory != NULL && request->project_kind != NULL &&
         request->main_source_path != NULL &&
         request->interrupt_header_path != NULL &&
         request->source_paths.count > 0 &&
         request->hex_output_path != NULL &&
         request->map_output_path != NULL && request->log_output_path != NULL &&
         (request->source_paths.count == 0 ||
          request->source_paths.items != NULL) &&
         (request->library_source_paths.count == 0 ||
          request->library_source_paths.items != NULL) &&
         (request->compile_arguments.count == 0 ||
          request->compile_arguments.items != NULL) &&
         (request->link_arguments.count == 0 ||
          request->link_arguments.items != NULL);
}

static int pb_owned_request_valid(const pb_owned_request *request) {
  return request != NULL && request->working_directory != NULL &&
         request->resource_directory != NULL && request->project_kind != NULL &&
         request->main_source_path != NULL &&
         request->interrupt_header_path != NULL &&
         request->hex_output_path != NULL &&
         request->map_output_path != NULL && request->log_output_path != NULL &&
         (request->source_count == 0 || request->source_paths != NULL) &&
         (request->library_source_count == 0 ||
          request->library_source_paths != NULL) &&
         (request->compile_argument_count == 0 ||
          request->compile_arguments != NULL) &&
         (request->link_argument_count == 0 || request->link_arguments != NULL);
}

static void pb_emit(void *context,
                    pb_sdcc_stage stage,
                    pb_sdcc_level level,
                    int current,
                    int total,
                    const char *file_name,
                    const char *message) {
  pb_sdcc_operation *operation = context;
  pthread_mutex_lock(&operation->mutex);
  if (operation->event_count == PB_EVENT_CAPACITY) {
    operation->event_head = (operation->event_head + 1) % PB_EVENT_CAPACITY;
    operation->event_count--;
  }
  const unsigned int index =
      (operation->event_head + operation->event_count) % PB_EVENT_CAPACITY;
  pb_owned_event *event = &operation->events[index];
  event->stage = stage;
  event->level = level;
  event->current = current;
  event->total = total;
  snprintf(event->file_name,
           sizeof(event->file_name),
           "%s",
           file_name == NULL ? "" : file_name);
  snprintf(event->message,
           sizeof(event->message),
           "%s",
           message == NULL ? "" : message);
  operation->event_count++;
  pthread_mutex_unlock(&operation->mutex);
}

static void *pb_worker(void *context) {
  pb_sdcc_operation *operation = context;
  pb_sdcc_request request = {
      .working_directory = operation->request.working_directory,
      .resource_directory = operation->request.resource_directory,
      .project_kind = operation->request.project_kind,
      .main_source_path = operation->request.main_source_path,
      .interrupt_header_path = operation->request.interrupt_header_path,
      .source_paths = {(const char *const *)operation->request.source_paths,
                       operation->request.source_count},
      .library_source_paths = {
          (const char *const *)operation->request.library_source_paths,
          operation->request.library_source_count},
      .compile_arguments = {
          (const char *const *)operation->request.compile_arguments,
          operation->request.compile_argument_count},
      .link_arguments = {
          (const char *const *)operation->request.link_arguments,
          operation->request.link_argument_count},
      .hex_output_path = operation->request.hex_output_path,
      .map_output_path = operation->request.map_output_path,
      .log_output_path = operation->request.log_output_path,
  };
  pb_emit(operation,
          PB_SDCC_STAGE_PREPARING,
          PB_SDCC_LEVEL_INFO,
          0,
          0,
          NULL,
          "Preparing in-process SDCC C251 build");

  FILE *log_stream = fopen(operation->request.log_output_path, "w");
  int saved_stdout = -1;
  int saved_stderr = -1;
  if (log_stream != NULL) {
    fflush(stdout);
    fflush(stderr);
    saved_stdout = dup(STDOUT_FILENO);
    saved_stderr = dup(STDERR_FILENO);
    if (saved_stdout >= 0 && saved_stderr >= 0) {
      (void)dup2(fileno(log_stream), STDOUT_FILENO);
      (void)dup2(fileno(log_stream), STDERR_FILENO);
      setvbuf(stdout, NULL, _IOLBF, 0);
      setvbuf(stderr, NULL, _IOLBF, 0);
    }
  }

  int warnings = 0;
  char message[PB_MESSAGE_CAPACITY] = {0};
  int result = pb_sdcc_pipeline_execute(&request,
                                        &operation->cancel_requested,
                                        pb_emit,
                                        operation,
                                        &warnings,
                                        message,
                                        sizeof(message));
  fflush(stdout);
  fflush(stderr);
  if (saved_stdout >= 0) {
    (void)dup2(saved_stdout, STDOUT_FILENO);
    close(saved_stdout);
  }
  if (saved_stderr >= 0) {
    (void)dup2(saved_stderr, STDERR_FILENO);
    close(saved_stderr);
  }
  if (log_stream != NULL) fclose(log_stream);
  if (atomic_load(&operation->cancel_requested)) {
    result = PB_SDCC_CANCELED;
    snprintf(message, sizeof(message), "%s", "Build canceled");
    unlink(operation->request.hex_output_path);
    unlink(operation->request.map_output_path);
  }

  pthread_mutex_lock(&operation->mutex);
  operation->status = result;
  operation->exit_code = result == PB_SDCC_OK ? 0 : result;
  operation->error_count = result == PB_SDCC_OK ? 0 : 1;
  operation->warning_count = warnings;
  snprintf(operation->result_error_code,
           sizeof(operation->result_error_code),
           "%s",
           result == PB_SDCC_OK ? "" : "native_pipeline_failed");
  operation->complete = 1;
  snprintf(operation->result_message,
           sizeof(operation->result_message),
           "%s",
           message);
  pthread_mutex_unlock(&operation->mutex);

  pthread_mutex_lock(&g_build_mutex);
  g_build_active = 0;
  pthread_mutex_unlock(&g_build_mutex);
  return NULL;
}

uint32_t pb_sdcc_api_version(void) { return PB_SDCC_API_VERSION; }

const char *pb_sdcc_build_fingerprint(void) {
  return "sdcc-c251:912a589d4080c9cd5c5c1faf871c62dd5023580d;ffi:4;service:1;embedded-host:1;android-abi:"
         PB_SDCC_ANDROID_ABI ";stage-object:" PB_SDCC_STAGE_SHA256
         ";pipeline-enabled:"
#if PB_SDCC_PIPELINE_ENABLED
         "1"
#else
         "0"
#endif
         ";stages-linked:"
#if PB_SDCC_STAGES_LINKED
         "1";
#else
         "0";
#endif
}

int32_t pb_sdcc_is_available(void) {
  return PB_SDCC_PIPELINE_ENABLED && PB_SDCC_STAGES_LINKED &&
         pb_sdcc_stage_entries_available() &&
         pb_sdcc_embedded_host_self_test();
}

pb_sdcc_status pb_sdcc_start(const pb_sdcc_request *request,
                             pb_sdcc_operation **operation) {
  if (!pb_request_valid(request) || operation == NULL) {
    return PB_SDCC_INVALID_ARGUMENT;
  }
  if (!pb_sdcc_is_available()) return PB_SDCC_UNAVAILABLE;
  pthread_mutex_lock(&g_build_mutex);
  if (g_build_active) {
    pthread_mutex_unlock(&g_build_mutex);
    return PB_SDCC_BUSY;
  }
  g_build_active = 1;
  pthread_mutex_unlock(&g_build_mutex);

  pb_sdcc_operation *created = calloc(1, sizeof(*created));
  if (created == NULL) goto allocation_failed;
  pthread_mutex_init(&created->mutex, NULL);
  atomic_init(&created->cancel_requested, 0);
  created->status = PB_SDCC_RUNNING;
  created->request.working_directory = pb_copy_string(request->working_directory);
  created->request.resource_directory = pb_copy_string(request->resource_directory);
  created->request.project_kind = pb_copy_string(request->project_kind);
  created->request.main_source_path = pb_copy_string(request->main_source_path);
  created->request.interrupt_header_path =
      pb_copy_string(request->interrupt_header_path);
  created->request.source_count = request->source_paths.count;
  created->request.source_paths = pb_copy_strings(&request->source_paths);
  created->request.library_source_count = request->library_source_paths.count;
  created->request.library_source_paths =
      pb_copy_strings(&request->library_source_paths);
  created->request.compile_argument_count = request->compile_arguments.count;
  created->request.compile_arguments =
      pb_copy_strings(&request->compile_arguments);
  created->request.link_argument_count = request->link_arguments.count;
  created->request.link_arguments = pb_copy_strings(&request->link_arguments);
  created->request.hex_output_path = pb_copy_string(request->hex_output_path);
  created->request.map_output_path = pb_copy_string(request->map_output_path);
  created->request.log_output_path = pb_copy_string(request->log_output_path);
  if (!pb_owned_request_valid(&created->request)) {
    pb_free_request(&created->request);
    pthread_mutex_destroy(&created->mutex);
    free(created);
    goto allocation_failed;
  }
  if (pthread_create(&created->thread, NULL, pb_worker, created) != 0) {
    pb_free_request(&created->request);
    pthread_mutex_destroy(&created->mutex);
    free(created);
    goto allocation_failed;
  }
  created->thread_started = 1;
  *operation = created;
  return PB_SDCC_OK;

allocation_failed:
  pthread_mutex_lock(&g_build_mutex);
  g_build_active = 0;
  pthread_mutex_unlock(&g_build_mutex);
  return PB_SDCC_IO_ERROR;
}

pb_sdcc_status pb_sdcc_poll_event(pb_sdcc_operation *operation,
                                  pb_sdcc_event *event) {
  if (operation == NULL || event == NULL) return PB_SDCC_INVALID_ARGUMENT;
  pthread_mutex_lock(&operation->mutex);
  if (operation->event_count == 0) {
    const int complete = operation->complete;
    pthread_mutex_unlock(&operation->mutex);
    return complete ? PB_SDCC_COMPLETE : PB_SDCC_RUNNING;
  }
  pb_owned_event *source = &operation->events[operation->event_head];
  operation->event_head = (operation->event_head + 1) % PB_EVENT_CAPACITY;
  operation->event_count--;
  memcpy(operation->last_event_message,
         source->message,
         sizeof(operation->last_event_message));
  memcpy(operation->last_event_file_name,
         source->file_name,
         sizeof(operation->last_event_file_name));
  event->stage = source->stage;
  event->level = source->level;
  event->current = source->current;
  event->total = source->total;
  event->file_name = operation->last_event_file_name;
  event->message = operation->last_event_message;
  pthread_mutex_unlock(&operation->mutex);
  return PB_SDCC_EVENT_AVAILABLE;
}

pb_sdcc_status pb_sdcc_cancel(pb_sdcc_operation *operation) {
  if (operation == NULL) return PB_SDCC_INVALID_ARGUMENT;
  atomic_store(&operation->cancel_requested, 1);
  return PB_SDCC_OK;
}

pb_sdcc_status pb_sdcc_get_result(pb_sdcc_operation *operation,
                                  pb_sdcc_result *result) {
  if (operation == NULL || result == NULL) return PB_SDCC_INVALID_ARGUMENT;
  pthread_mutex_lock(&operation->mutex);
  if (!operation->complete) {
    pthread_mutex_unlock(&operation->mutex);
    return PB_SDCC_RUNNING;
  }
  result->status = operation->status;
  result->exit_code = operation->exit_code;
  result->error_count = operation->error_count;
  result->warning_count = operation->warning_count;
  result->hex_path = operation->request.hex_output_path;
  result->map_path = operation->request.map_output_path;
  result->log_path = operation->request.log_output_path;
  result->error_code = operation->result_error_code;
  result->message = operation->result_message;
  pthread_mutex_unlock(&operation->mutex);
  return PB_SDCC_COMPLETE;
}

void pb_sdcc_destroy(pb_sdcc_operation *operation) {
  if (operation == NULL) return;
  atomic_store(&operation->cancel_requested, 1);
  if (operation->thread_started && !operation->thread_joined) {
    pthread_join(operation->thread, NULL);
    operation->thread_joined = 1;
  }
  pb_free_request(&operation->request);
  pthread_mutex_destroy(&operation->mutex);
  free(operation);
}
